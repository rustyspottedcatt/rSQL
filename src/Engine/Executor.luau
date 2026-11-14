--!strict
--[[
	Runs parsed statements against a storage adapter.

	SELECT runs in this order:

	    fetch (key lookup or scan) -> JOIN -> WHERE -> GROUP BY / aggregates
	    -> HAVING -> project -> DISTINCT -> ORDER BY -> OFFSET / LIMIT

	JOINs on an equality (`a.x = b.y`) build a hash table of the joined
	table, so they cost one scan of each side. Other join conditions fall back
	to comparing every pair.
]]

local Ast = require("../SQL/Ast")
local Errors = require("../SQL/Errors")
local Schema = require("./Schema")
local Types = require("./Types")
local Expression = require("./Expression")
local Text = require("../Util/Text")
local Planner = require("./Planner")
local Adapter = require("../Storage/Adapter")

type Expr = Ast.Expr
type Statement = Ast.Statement
type Row = Adapter.Row
type Params = Expression.Params

export type Result = {
	kind: string,
	rows: { Row },
	columns: { string },
	affected: number,
	insertIds: { any },
	lastInsertId: any?,
	message: string?,
	plan: { string }?,
}

export type Options = {
	-- CREATE TABLE on an existing table keeps it and warns (1.x scripts run it on every boot)
	createIsNoop: boolean?,
	-- tables without a declared PRIMARY KEY use their first column (1.x behavior)
	firstColumnKey: boolean?,
	createOptions: Adapter.CreateOptions?,
	warn: ((message: string) -> ())?,
}

local Executor = {}

local function result(kind: string): Result
	return { kind = kind, rows = {}, columns = {}, affected = 0, insertIds = {} }
end

local function semantic(message: string, pos: number?, query: string): never
	return Errors.raise("semantic", message, pos, query)
end

local function tableInfo(adapter: Adapter.Adapter, name: string, pos: number?, query: string): Adapter.TableInfo
	local info = adapter:getTable(name)
	if not info then
		local hint = Text.closest(name, adapter:listTables(), 2)
		semantic("no table named " .. name .. (if hint then " (did you mean " .. hint .. "?)" else ""), pos, query)
	end
	return info :: Adapter.TableInfo
end

-- Values that identify a group or a DISTINCT row.
local function groupKey(values: { any }, n: number): string
	local parts = table.create(n)
	for i = 1, n do
		local v = values[i]
		parts[i] = if v == nil then "\0" else typeof(v) .. ":" .. tostring(v)
	end
	return table.concat(parts, "\1")
end

local function fetch(
	adapter: Adapter.Adapter,
	stmt: Statement,
	schema: Schema.TableSchema,
	alias: string,
	params: Params,
	query: string
): ({ Row }, Planner.Access)
	local access = Planner.access(stmt.where, schema, alias)
	if access.kind == "lookup" then
		local keys = Planner.keys(access, schema, params, query)
		if #keys == 0 then
			return {}, access
		end
		return adapter:get(schema.name, keys), access
	end
	return adapter:scan(schema.name), access
end

-- SELECT -------------------------------------------------------------------------------

type Output = { name: string, get: Expression.Compiled }

local function runSelect(adapter: Adapter.Adapter, stmt: Statement, params: Params, query: string): Result
	local from = stmt.from :: Ast.TableRef
	local mainInfo = tableInfo(adapter, from.name, from.pos, query)
	local sources: { Expression.Source } = { { alias = from.alias or from.name, schema = mainInfo.schema } }
	local joins: { Ast.Join } = stmt.joins or {}
	for _, join in joins do
		local info = tableInfo(adapter, join.target.name, join.target.pos, query)
		table.insert(sources, { alias = join.target.alias or join.target.name, schema = info.schema })
	end
	local multi = #sources > 1

	-- aggregates used anywhere in the output
	local aggregateNodes: { Expr } = {}
	for _, item in stmt.items :: { Ast.SelectItem } do
		Expression.findAggregates(item.expr, aggregateNodes)
	end
	Expression.findAggregates(stmt.having, aggregateNodes)
	local orderItems: { Ast.OrderItem } = stmt.orderBy or {}
	for _, o in orderItems do
		Expression.findAggregates(o.expr, aggregateNodes)
	end
	local slots: { [Expr]: number } = {}
	for i, n in aggregateNodes do
		slots[n] = i
	end
	local grouped = #aggregateNodes > 0 or stmt.groupBy ~= nil
	local scope: Expression.Scope = { sources = sources, query = query, aggregates = slots }
	local rowScope: Expression.Scope = { sources = sources, query = query }

	-- 1. fetch
	local baseRows: { Row }
	local access: Planner.Access
	if multi then
		baseRows, access = adapter:scan(mainInfo.schema.name), { kind = "scan", detail = "full scan of " .. from.name }
	else
		baseRows, access = fetch(adapter, stmt, mainInfo.schema, sources[1].alias, params, query)
	end
	local scanned = #baseRows

	-- 2. joins: rows become arrays with one entry per table
	local rows: { any } = baseRows
	if multi then
		local tuples: { any } = table.create(#baseRows)
		for i, r in baseRows do
			tuples[i] = { r }
		end
		for j, join in joins do
			local index = j + 1
			local right = adapter:scan(sources[index].schema.name)
			scanned += #right
			local on = join.on
			local hashed = false
			local nextTuples: { any } = {}
			-- equality join: hash the joined table on its column
			if on.kind == "binary" and on.op == "=" then
				local l, r = on.left :: Expr, on.right :: Expr
				local function side(e: Expr): number?
					if e.kind ~= "column" then
						return nil
					end
					local ok, which = pcall(function(): any
						return (Expression.resolveColumn(rowScope, e))
					end)
					return if ok then which else nil
				end
				local ls, rs = side(l), side(r)
				local inner: Expr?, outer: Expr? = nil, nil
				if rs == index and ls and ls < index then
					inner, outer = r, l
				elseif ls == index and rs and rs < index then
					inner, outer = l, r
				end
				if inner and outer then
					hashed = true
					local _, innerColumn = Expression.resolveColumn(rowScope, inner)
					local outerGet = Expression.compile(outer, rowScope)
					local buckets: { [string]: { Row } } = {}
					for _, row in right do
						local v = row[innerColumn]
						if v ~= nil then
							local key = Types.key(if typeof(v) == "string" and tonumber(v) then tonumber(v) else v)
							buckets[key] = buckets[key] or {}
							table.insert(buckets[key], row)
						end
					end
					for _, tuple in tuples do
						local v = outerGet(tuple, params)
						local matches = if v == nil
							then nil
							else buckets[Types.key(
								if typeof(v) == "string" and tonumber(v) then tonumber(v) else v
							)]
						if matches then
							for _, m in matches do
								local t = table.clone(tuple)
								t[index] = m
								table.insert(nextTuples, t)
							end
						elseif join.type == "left" then
							table.insert(nextTuples, tuple)
						end
					end
				end
			end
			if not hashed then
				local cond = Expression.compile(on, rowScope)
				for _, tuple in tuples do
					local matched = false
					for _, row in right do
						local t = table.clone(tuple)
						t[index] = row
						if Types.truthy(cond(t, params)) then
							matched = true
							table.insert(nextTuples, t)
						end
					end
					if not matched and join.type == "left" then
						table.insert(nextTuples, tuple)
					end
				end
			end
			tuples = nextTuples
		end
		rows = tuples
	end

	-- 3. where
	if stmt.where then
		local where = Expression.compile(stmt.where, rowScope)
		local kept = {}
		for _, row in rows do
			if Types.truthy(where(row, params)) then
				table.insert(kept, row)
			end
		end
		rows = kept
	end

	-- 4. outputs
	local outputs: { Output } = {}
	for _, item in stmt.items :: { Ast.SelectItem } do
		local e = item.expr
		if e.kind == "star" then
			if grouped then
				semantic("SELECT * can't be combined with GROUP BY or aggregates", e.pos, query)
			end
			for index, source in sources do
				if e.table == nil or string.lower(e.table) == string.lower(source.alias) then
					for _, column in Schema.visibleColumns(source.schema) do
						local name = column.name
						local columnName = column.name
						if multi then
							for _, out in outputs do
								if out.name == name then
									name = source.alias .. "." .. column.name
								end
							end
						end
						table.insert(outputs, {
							name = name,
							get = if multi
								then function(row)
									local r = row[index]
									return if r then r[columnName] else nil
								end
								else function(row)
									return row[columnName]
								end,
						})
					end
				end
			end
		else
			local name = item.alias
				or (if e.kind == "column" then select(2, Expression.resolveColumn(rowScope, e)) else Expression.text(e))
			table.insert(outputs, { name = name, get = Expression.compile(e, scope) })
		end
	end

	-- 5. grouping
	type Record = { row: any, agg: { any }? }
	local records: { Record } = {}
	if grouped then
		local groupExprs: { Expression.Compiled } = {}
		local groupBy: { Expr } = stmt.groupBy or {}
		for i, g in groupBy do
			groupExprs[i] = Expression.compile(g, rowScope)
		end
		type Group = { row: any, rows: { any } }
		local order: { Group } = {}
		local byKey: { [string]: Group } = {}
		for _, row in rows do
			local values = table.create(#groupExprs)
			for i, g in groupExprs do
				values[i] = g(row, params)
			end
			local key = groupKey(values, #groupExprs)
			local group: Group? = byKey[key]
			if group == nil then
				local fresh: Group = { row = row, rows = {} }
				byKey[key] = fresh
				table.insert(order, fresh)
				group = fresh
			end
			table.insert((group :: Group).rows, row)
		end
		if #order == 0 and stmt.groupBy == nil then
			table.insert(order, { row = if multi then {} else {}, rows = {} })
		end
		-- aggregate argument getters
		local argGetters: { Expression.Compiled? } = {}
		for i, n in aggregateNodes do
			local args = n.args :: { Expr }
			if #args == 1 and args[1].kind ~= "star" then
				argGetters[i] = Expression.compile(args[1], rowScope)
			elseif n.name ~= "COUNT" then
				semantic(n.name :: string .. "() needs a column or expression", n.pos, query)
			end
		end
		local having = if stmt.having then Expression.compile(stmt.having, scope) else nil
		for _, group in order do
			local agg: { any } = table.create(#aggregateNodes)
			for i, n in aggregateNodes do
				local getter = argGetters[i]
				local name = n.name
				local seen: { [string]: boolean }? = if n.distinct then {} else nil
				local count: number, sum: number, best: any = 0, 0, nil
				for _, row in group.rows do
					local v = if getter then getter(row, params) else true
					if v ~= nil then
						local fresh = true
						if seen then
							local k = typeof(v) .. ":" .. tostring(v)
							fresh = not seen[k]
							seen[k] = true
						end
						if fresh then
							count += 1
							if name == "SUM" or name == "AVG" then
								local x = tonumber(v)
								if x == nil then
									semantic(name .. "() of a non-number value '" .. tostring(v) .. "'", n.pos, query)
								end
								sum += x :: number
							elseif name == "MIN" then
								if best == nil or Types.sortCompare(v, best) < 0 then
									best = v
								end
							elseif name == "MAX" then
								if best == nil or Types.sortCompare(v, best) > 0 then
									best = v
								end
							end
						end
					end
				end
				if name == "COUNT" then
					agg[i] = count
				elseif name == "SUM" then
					agg[i] = if count > 0 then sum else nil
				elseif name == "AVG" then
					agg[i] = if count > 0 then sum / count else nil
				else
					agg[i] = best
				end
			end
			if having == nil or Types.truthy(having(group.row, params, agg)) then
				table.insert(records, { row = group.row, agg = agg })
			end
		end
	else
		if stmt.having then
			semantic("HAVING needs GROUP BY or an aggregate", stmt.having.pos, query)
		end
		for i, row in rows do
			records[i] = { row = row }
		end
	end

	-- 6. project
	local columns: { string } = {}
	for i, out in outputs do
		columns[i] = out.name
	end
	type Projected = { values: { any }, record: Record }
	local projected: { Projected } = table.create(#records)
	for i, rec in records do
		local values = table.create(#outputs)
		for j, out in outputs do
			values[j] = out.get(rec.row, params, rec.agg)
		end
		projected[i] = { values = values, record = rec }
	end

	-- 7. distinct
	if stmt.distinct then
		local seen: { [string]: boolean } = {}
		local unique = {}
		for _, p in projected do
			local key = groupKey(p.values, #outputs)
			if not seen[key] then
				seen[key] = true
				table.insert(unique, p)
			end
		end
		projected = unique
	end

	-- 8. order by: output names and positions first, then any expression
	if stmt.orderBy then
		type Key = { position: number?, get: Expression.Compiled?, desc: boolean }
		local keys: { Key } = {}
		for _, o in stmt.orderBy do
			local e = o.expr
			local position: number? = nil
			if e.kind == "literal" and type(e.value) == "number" then
				local p = e.value :: number
				position = p
				if p < 1 or p > #outputs or p % 1 ~= 0 then
					semantic("ORDER BY position " .. tostring(e.value) .. " is out of range", e.pos, query)
				end
			elseif e.kind == "column" and e.table == nil then
				for j, out in outputs do
					if string.lower(out.name) == string.lower(e.name :: string) then
						position = j
						break
					end
				end
			end
			table.insert(keys, {
				position = position,
				get = if position then nil else Expression.compile(e, if grouped then scope else rowScope),
				desc = o.desc,
			})
		end
		local sortValues: { [Projected]: { any } } = {}
		for _, p in projected do
			local values = table.create(#keys)
			for k, key in keys do
				values[k] = if key.position
					then p.values[key.position]
					else (key.get :: Expression.Compiled)(p.record.row, params, p.record.agg)
			end
			sortValues[p] = values
		end
		local positions: { [Projected]: number } = {}
		for i, p in projected do
			positions[p] = i
		end
		table.sort(projected, function(a, b)
			local va, vb = sortValues[a], sortValues[b]
			for k, key in keys do
				local c = Types.sortCompare(va[k], vb[k])
				if c ~= 0 then
					if key.desc then
						return c > 0
					end
					return c < 0
				end
			end
			return positions[a] < positions[b]
		end)
	end

	-- 9. offset / limit
	local constantScope: Expression.Scope = { sources = {}, query = query }
	local offset = if stmt.offset then tonumber(Expression.compile(stmt.offset, constantScope)(nil, params)) or 0 else 0
	local limit = if stmt.limit then tonumber(Expression.compile(stmt.limit, constantScope)(nil, params)) else nil
	local out = result("select")
	out.columns = columns
	local first = math.max(0, math.floor(offset)) + 1
	local last = if limit then math.min(#projected, first + math.max(0, math.floor(limit)) - 1) else #projected
	for i = first, last do
		local p = projected[i]
		local row: Row = {}
		for j, name in columns do
			row[name] = p.values[j]
		end
		table.insert(out.rows, row)
	end
	out.affected = 0
	out.plan = { access.detail, string.format("%d rows read, %d returned", scanned, #out.rows) }
	return out
end

-- INSERT / UPDATE / DELETE ---------------------------------------------------------------

local function uniqueColumns(schema: Schema.TableSchema): { Schema.Column }
	local out = {}
	for _, c in schema.columns do
		if c.unique and not c.primaryKey then
			table.insert(out, c)
		end
	end
	return out
end

local function runInsert(adapter: Adapter.Adapter, stmt: Statement, params: Params, query: string): Result
	local info = tableInfo(adapter, stmt.table :: string, stmt.pos, query)
	local schema = info.schema
	local names: { string } = {}
	if stmt.columns then
		for _, name in stmt.columns do
			local column = Schema.column(schema, name)
			if not column then
				semantic(string.format("table %s has no column %s", schema.name, name), stmt.pos, query)
			end
			table.insert(names, (column :: Schema.Column).name)
		end
	else
		names = Schema.columnNames(schema)
	end
	local scope: Expression.Scope = { sources = {}, query = query }
	local auto = Schema.autoincrementColumn(schema)
	local built: { Row } = {}
	local needIds = 0
	for _, exprs in stmt.rows :: { { Expr } } do
		if #exprs ~= #names then
			semantic(string.format("expected %d values, got %d", #names, #exprs), exprs[1] and exprs[1].pos, query)
		end
		local row: Row = {}
		for i, e in exprs do
			row[names[i]] = Expression.compile(e, scope)(nil, params)
		end
		if auto and row[auto.name] == nil then
			needIds += 1
		end
		table.insert(built, row)
	end
	if auto and needIds > 0 then
		local nextId = adapter:allocateIds(schema.name, needIds)
		for _, row in built do
			if row[auto.name] == nil then
				row[auto.name] = nextId
				nextId += 1
			end
		end
	end
	local items: { { key: string, row: Row } } = {}
	local out = result("insert")
	for i, row in built do
		local checked = Schema.checkRow(schema, row)
		local keyValue = checked[schema.primaryKey]
		if keyValue == nil then
			semantic("primary key " .. schema.primaryKey .. " can't be NULL", stmt.pos, query)
		end
		items[i] = { key = Types.key(keyValue), row = checked }
		out.insertIds[i] = keyValue
	end
	local uniques = uniqueColumns(schema)
	if #uniques > 0 then
		local existing = adapter:scan(schema.name)
		for _, c in uniques do
			local taken: { [string]: boolean } = {}
			for _, row in existing do
				if row[c.name] ~= nil then
					taken[Types.key(row[c.name])] = true
				end
			end
			for _, item in items do
				local v = item.row[c.name]
				if v ~= nil then
					local k = Types.key(v)
					if taken[k] then
						Errors.raise(
							"constraint",
							string.format("%s.%s must be unique ('%s' is taken)", schema.name, c.name, k)
						)
					end
					taken[k] = true
				end
			end
		end
	end
	adapter:insert(schema.name, items)
	out.affected = #items
	out.lastInsertId = out.insertIds[#out.insertIds]
	out.message = string.format("inserted %d row%s into %s", #items, if #items == 1 then "" else "s", schema.name)
	return out
end

local function runUpdate(adapter: Adapter.Adapter, stmt: Statement, params: Params, query: string): Result
	local info = tableInfo(adapter, stmt.table :: string, stmt.pos, query)
	local schema = info.schema
	local scope: Expression.Scope = { sources = { { alias = schema.name, schema = schema } }, query = query }
	type Set = { column: string, get: Expression.Compiled }
	local sets: { Set } = {}
	local uniqueSet: { string } = {}
	for _, s in stmt.sets :: { any } do
		local column = Schema.column(schema, s.column)
		if not column then
			semantic(string.format("table %s has no column %s", schema.name, s.column), s.pos, query)
		end
		local c = column :: Schema.Column
		if c.unique and not c.primaryKey then
			table.insert(uniqueSet, c.name)
		end
		table.insert(sets, { column = c.name, get = Expression.compile(s.expr, scope) })
	end
	local where = if stmt.where then Expression.compile(stmt.where, scope) else nil
	local access = Planner.access(stmt.where, schema, schema.name)
	local keys = if access.kind == "lookup" then Planner.keys(access, schema, params, query) else nil
	local taken: { [string]: { [string]: boolean } } = {}
	if #uniqueSet > 0 then
		for _, row in adapter:scan(schema.name) do
			for _, name in uniqueSet do
				taken[name] = taken[name] or {}
				if row[name] ~= nil then
					taken[name][Types.key(row[name])] = true
				end
			end
		end
	end
	local out = result("update")
	if keys and #keys == 0 then
		out.message = "updated 0 rows in " .. schema.name
		return out
	end
	out.affected = adapter:modify(schema.name, keys, function(row)
		if where and not Types.truthy(where(row, params)) then
			return "keep", nil
		end
		local newRow = table.clone(row)
		for _, s in sets do
			newRow[s.column] = s.get(row, params)
		end
		local checked = Schema.checkRow(schema, newRow)
		for _, name in uniqueSet do
			local v = checked[name]
			if v ~= nil and v ~= row[name] and taken[name][Types.key(v)] then
				Errors.raise(
					"constraint",
					string.format("%s.%s must be unique ('%s' is taken)", schema.name, name, Types.key(v))
				)
			end
		end
		return "update", checked
	end)
	out.message =
		string.format("updated %d row%s in %s", out.affected, if out.affected == 1 then "" else "s", schema.name)
	out.plan = { access.detail }
	return out
end

local function runDelete(adapter: Adapter.Adapter, stmt: Statement, params: Params, query: string): Result
	local info = tableInfo(adapter, stmt.table :: string, stmt.pos, query)
	local schema = info.schema
	local scope: Expression.Scope = { sources = { { alias = schema.name, schema = schema } }, query = query }
	local where = if stmt.where then Expression.compile(stmt.where, scope) else nil
	local access = Planner.access(stmt.where, schema, schema.name)
	local keys = if access.kind == "lookup" then Planner.keys(access, schema, params, query) else nil
	local out = result("delete")
	if keys and #keys == 0 then
		out.message = "deleted 0 rows from " .. schema.name
		return out
	end
	out.affected = adapter:modify(schema.name, keys, function(row)
		if where and not Types.truthy(where(row, params)) then
			return "keep", nil
		end
		return "delete", nil
	end)
	out.message =
		string.format("deleted %d row%s from %s", out.affected, if out.affected == 1 then "" else "s", schema.name)
	out.plan = { access.detail }
	return out
end

-- DDL --------------------------------------------------------------------------------

local function runCreate(adapter: Adapter.Adapter, stmt: Statement, query: string, options: Options): Result
	local name = stmt.table :: string
	local out = result("create")
	if adapter:getTable(name) then
		if stmt.ifNotExists then
			out.message = "table " .. name .. " already exists"
			return out
		elseif options.createIsNoop then
			if options.warn then
				options.warn(
					"CREATE TABLE " .. name .. " ran on an existing table; kept its data (rSQL 1.x used to wipe it)"
				)
			end
			out.message = "table " .. name .. " already exists"
			return out
		end
		semantic("table " .. name .. " already exists (use CREATE TABLE IF NOT EXISTS)", stmt.pos, query)
	end
	local schema = Schema.fromDefinition(name, stmt.columnDefs :: { Ast.ColumnDef }, options.firstColumnKey)
	adapter:createTable(schema, options.createOptions)
	out.message = "created table " .. name
	return out
end

local function runAlter(adapter: Adapter.Adapter, stmt: Statement, query: string): Result
	local name = stmt.table :: string
	local info = tableInfo(adapter, name, stmt.pos, query)
	local schema = table.clone(info.schema)
	schema.columns = table.clone(schema.columns)
	schema.legacy = nil
	local out = result("alter")
	if stmt.action == "add" then
		local def = stmt.columnDef :: Ast.ColumnDef
		if Schema.column(schema, def.name) then
			semantic("column " .. def.name .. " already exists", def.pos, query)
		end
		if def.primaryKey then
			semantic("can't add a PRIMARY KEY column to an existing table", def.pos, query)
		end
		local column = Schema.fromDefinition(name, { def }).columns[2]
		if column.notNull and column.default == nil then
			semantic("a NOT NULL column added to an existing table needs a DEFAULT", def.pos, query)
		end
		table.insert(schema.columns, column)
		local default = column.default
		adapter:setSchema(
			name,
			schema,
			if default ~= nil
				then function(row)
					local r = table.clone(row)
					if r[column.name] == nil then
						r[column.name] = default
					end
					return r
				end
				else nil
		)
		out.message = string.format("added column %s to %s", column.name, name)
	elseif stmt.action == "drop" then
		local column = Schema.column(schema, stmt.column :: string)
		if not column then
			semantic("table " .. name .. " has no column " .. tostring(stmt.column), stmt.pos, query)
		end
		local c = column :: Schema.Column
		if c.name == schema.primaryKey then
			semantic("can't drop the primary key column " .. c.name, stmt.pos, query)
		end
		local i = table.find(schema.columns, c) :: number
		table.remove(schema.columns, i)
		adapter:setSchema(name, schema, function(row)
			local r = table.clone(row)
			r[c.name] = nil
			return r
		end)
		out.message = string.format("dropped column %s from %s", c.name, name)
	else
		local column = Schema.column(schema, stmt.column :: string)
		if not column then
			semantic("table " .. name .. " has no column " .. tostring(stmt.column), stmt.pos, query)
		end
		local c = column :: Schema.Column
		local newName = stmt.newName :: string
		Schema.validateName(newName, "column")
		if Schema.column(schema, newName) then
			semantic("column " .. newName .. " already exists", stmt.pos, query)
		end
		local i = table.find(schema.columns, c) :: number
		local renamed = table.clone(c)
		renamed.name = newName
		schema.columns[i] = renamed
		if schema.primaryKey == c.name then
			schema.primaryKey = newName
		end
		local oldName = c.name
		adapter:setSchema(name, schema, function(row)
			local r = table.clone(row)
			r[newName] = r[oldName]
			r[oldName] = nil
			return r
		end)
		out.message = string.format("renamed %s.%s to %s", name, oldName, newName)
	end
	return out
end

local function describeTable(adapter: Adapter.Adapter, stmt: Statement, query: string): Result
	local info = tableInfo(adapter, stmt.table :: string, stmt.pos, query)
	local out = result("describe")
	out.columns = { "column", "type", "key", "nullable", "default" }
	for _, c in Schema.visibleColumns(info.schema) do
		table.insert(out.rows, {
			column = c.name,
			type = c.type,
			key = if c.primaryKey then "PRIMARY" elseif c.unique then "UNIQUE" else "",
			nullable = not c.notNull,
			default = c.default,
		})
	end
	out.message = string.format(
		"%s: %s layout%s",
		info.schema.name,
		info.layout,
		if info.shards then string.format(", %d shards", info.shards) else ""
	)
	return out
end

function Executor.execute(
	adapter: Adapter.Adapter,
	stmt: Statement,
	params: Params,
	query: string,
	options: Options?
): Result
	local opts = options or {}
	local kind = stmt.kind
	if kind == "select" then
		return runSelect(adapter, stmt, params, query)
	elseif kind == "insert" then
		return runInsert(adapter, stmt, params, query)
	elseif kind == "update" then
		return runUpdate(adapter, stmt, params, query)
	elseif kind == "delete" then
		return runDelete(adapter, stmt, params, query)
	elseif kind == "create" then
		return runCreate(adapter, stmt, query, opts)
	elseif kind == "drop" then
		local out = result("drop")
		if not adapter:dropTable(stmt.table :: string) and not stmt.ifExists then
			semantic("no table named " .. tostring(stmt.table), stmt.pos, query)
		end
		out.message = "dropped table " .. tostring(stmt.table)
		return out
	elseif kind == "truncate" then
		tableInfo(adapter, stmt.table :: string, stmt.pos, query)
		adapter:truncate(stmt.table :: string)
		local out = result("truncate")
		out.message = "emptied table " .. tostring(stmt.table)
		return out
	elseif kind == "alter" then
		return runAlter(adapter, stmt, query)
	elseif kind == "showTables" then
		local out = result("showTables")
		out.columns = { "name" }
		for _, name in adapter:listTables() do
			table.insert(out.rows, { name = name })
		end
		return out
	elseif kind == "describe" then
		return describeTable(adapter, stmt, query)
	elseif kind == "explain" then
		local inner = stmt.statement :: Statement
		local out = result("explain")
		out.columns = { "step" }
		local target = if inner.kind == "select" then (inner.from :: Ast.TableRef).name else inner.table :: string
		local info = tableInfo(adapter, target, inner.pos, query)
		local alias = if inner.kind == "select" then (inner.from :: Ast.TableRef).alias or target else target
		local access = Planner.access(inner.where, info.schema, alias)
		local steps: { string } = {}
		if inner.kind == "select" and inner.joins and #inner.joins > 0 then
			table.insert(steps, "full scan of " .. target)
			for _, join in inner.joins do
				table.insert(steps, string.format("%s join %s", string.upper(join.type), join.target.name))
			end
		else
			table.insert(
				steps,
				access.detail
					.. (
						if info.shards and access.kind == "scan"
							then string.format(" (%d shards)", info.shards)
							elseif info.shards then " (one shard per key)"
							else ""
					)
			)
		end
		if inner.where then
			table.insert(steps, "filter WHERE")
		end
		if inner.kind == "select" then
			if inner.groupBy then
				table.insert(steps, "group")
			end
			if inner.orderBy then
				table.insert(steps, "sort")
			end
			if inner.limit then
				table.insert(steps, "limit")
			end
		else
			table.insert(steps, inner.kind)
		end
		for _, step in steps do
			table.insert(out.rows, { step = step })
		end
		out.plan = steps
		return out
	end
	return semantic("unsupported statement " .. kind, stmt.pos, query)
end

return Executor
