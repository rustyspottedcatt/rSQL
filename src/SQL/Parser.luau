--!strict
--[[
	Recursive-descent parser: tokens in, one Statement out.

	Expressions use precedence climbing, lowest to highest:

	    OR
	    AND
	    NOT
	    = != < <= > >=  LIKE  IN  BETWEEN  IS [NOT] NULL
	    ||
	    + -
	    * / %
	    unary -

	Some keywords (KEY, TABLES, COLUMN, ...) can still be used as column or
	table names when nothing else fits, so a table with a column called "Key"
	keeps working.
]]

local Lexer = require("./Lexer")
local Errors = require("./Errors")
local Ast = require("./Ast")
local Text = require("../Util/Text")

type Token = Lexer.Token
type Expr = Ast.Expr
type Statement = Ast.Statement

local Parser = {}

local SOFT_KEYWORDS = {
	KEY = true,
	TABLES = true,
	COLUMN = true,
	ADD = true,
	RENAME = true,
	TO = true,
	SHOW = true,
	DESCRIBE = true,
	EXPLAIN = true,
	TRUNCATE = true,
	AUTOINCREMENT = true,
	OFFSET = true,
}

local COMPARISON = { ["="] = true, ["!="] = true, ["<"] = true, ["<="] = true, [">"] = true, [">="] = true }

type State = { tokens: { Token }, i: number, query: string, positional: number }

local function peek(s: State, ahead: number?): Token
	return s.tokens[s.i + (ahead or 0)] or s.tokens[#s.tokens]
end

local function advance(s: State): Token
	local t = s.tokens[s.i]
	if t.kind ~= "eof" then
		s.i += 1
	end
	return t
end

-- Closest keyword within two edits, for "did you mean" hints.
local KEYWORD_LIST: { string } = {}
for keyword in Lexer.KEYWORDS do
	table.insert(KEYWORD_LIST, keyword)
end
table.sort(KEYWORD_LIST)

local function suggest(word: string): string?
	if #word < 3 then
		return nil
	end
	return Text.closest(string.upper(word), KEYWORD_LIST, 2)
end

local function describe(t: Token): string
	if t.kind == "eof" then
		return "end of query"
	elseif t.kind == "ident" then
		local hint = suggest(t.value)
		if hint then
			return string.format("'%s' (did you mean %s?)", t.value, hint)
		end
	end
	return "'" .. t.value .. "'"
end

local function fail(s: State, message: string, t: Token?): never
	local at = t or peek(s)
	return Errors.raise("syntax", message, at.pos, s.query)
end

local function isKeyword(t: Token, word: string): boolean
	return t.kind == "keyword" and t.value == word
end

local function accept(s: State, word: string): boolean
	if isKeyword(peek(s), word) then
		advance(s)
		return true
	end
	return false
end

local function expect(s: State, word: string)
	local t = peek(s)
	if not isKeyword(t, word) then
		fail(s, string.format("expected %s, got %s", word, describe(t)))
	end
	advance(s)
end

local function acceptPunct(s: State, p: string): boolean
	local t = peek(s)
	if t.kind == "punct" and t.value == p then
		advance(s)
		return true
	end
	return false
end

local function expectPunct(s: State, p: string)
	if not acceptPunct(s, p) then
		fail(s, string.format("expected '%s', got %s", p, describe(peek(s))))
	end
end

local function acceptOp(s: State, op: string): boolean
	local t = peek(s)
	if t.kind == "op" and t.value == op then
		advance(s)
		return true
	end
	return false
end

local function identifier(s: State, what: string): (string, number)
	local t = peek(s)
	if t.kind == "ident" or (t.kind == "keyword" and SOFT_KEYWORDS[t.value]) then
		advance(s)
		return t.text or t.value, t.pos
	end
	if t.kind == "keyword" then
		return fail(
			s,
			string.format("expected %s, got keyword %s (quote it with backticks to use it as a name)", what, t.value)
		)
	end
	return fail(s, string.format("expected %s, got %s", what, describe(t)))
end

-- Expressions ------------------------------------------------------------------

local parseExpr: (s: State) -> Expr

local function node(kind: any, pos: number, fields: { [string]: any }?): Expr
	local n: any = fields or {}
	n.kind = kind
	n.pos = pos
	return n :: Expr
end

local function parsePrimary(s: State): Expr
	local t = peek(s)
	if t.kind == "number" then
		advance(s)
		return node("literal", t.pos, { value = t.number })
	elseif t.kind == "string" then
		advance(s)
		return node("literal", t.pos, { value = t.value })
	elseif t.kind == "param" then
		advance(s)
		if t.value == "?" then
			s.positional += 1
			return node("param", t.pos, { index = s.positional })
		end
		return node("param", t.pos, { name = t.value })
	elseif isKeyword(t, "NULL") then
		advance(s)
		return node("literal", t.pos, { value = nil })
	elseif isKeyword(t, "TRUE") or isKeyword(t, "FALSE") then
		advance(s)
		return node("literal", t.pos, { value = t.value == "TRUE" })
	elseif t.kind == "punct" and t.value == "(" then
		advance(s)
		local inner = parseExpr(s)
		expectPunct(s, ")")
		return inner
	elseif t.kind == "op" and t.value == "*" then
		advance(s)
		return node("star", t.pos)
	elseif t.kind == "ident" or (t.kind == "keyword" and SOFT_KEYWORDS[t.value]) then
		advance(s)
		local name = t.text or t.value
		-- function call
		if peek(s).kind == "punct" and peek(s).value == "(" then
			advance(s)
			local args: { Expr } = {}
			local distinct = accept(s, "DISTINCT")
			if not acceptPunct(s, ")") then
				repeat
					table.insert(args, parseExpr(s))
				until not acceptPunct(s, ",")
				expectPunct(s, ")")
			end
			return node("call", t.pos, { name = string.upper(name), args = args, distinct = distinct })
		end
		-- qualified column: table.column or table.*
		if acceptPunct(s, ".") then
			if acceptOp(s, "*") then
				return node("star", t.pos, { table = name })
			end
			local column = identifier(s, "a column name")
			return node("column", t.pos, { table = name, name = column })
		end
		return node("column", t.pos, { name = name })
	end
	return fail(s, "expected a value, column or expression, got " .. describe(t))
end

local function parseUnary(s: State): Expr
	local t = peek(s)
	if t.kind == "op" and t.value == "-" then
		advance(s)
		local operand = parseUnary(s)
		if operand.kind == "literal" and type(operand.value) == "number" then
			return node("literal", t.pos, { value = -operand.value })
		end
		return node("unary", t.pos, { op = "-", operand = operand })
	elseif t.kind == "op" and t.value == "+" then
		advance(s)
		return parseUnary(s)
	end
	return parsePrimary(s)
end

local function parseBinaryLevel(s: State, ops: { [string]: boolean }, nextLevel: (State) -> Expr): Expr
	local left = nextLevel(s)
	while true do
		local t = peek(s)
		if t.kind == "op" and ops[t.value] then
			advance(s)
			left = node("binary", t.pos, { op = t.value, left = left, right = nextLevel(s) })
		else
			return left
		end
	end
end

local MULT = { ["*"] = true, ["/"] = true, ["%"] = true }
local ADD = { ["+"] = true, ["-"] = true }
local CONCAT = { ["||"] = true }

local function parseMult(s: State): Expr
	return parseBinaryLevel(s, MULT, parseUnary)
end
local function parseAdd(s: State): Expr
	return parseBinaryLevel(s, ADD, parseMult)
end
local function parseConcat(s: State): Expr
	return parseBinaryLevel(s, CONCAT, parseAdd)
end

local function parseComparison(s: State): Expr
	local left = parseConcat(s)
	while true do
		local t = peek(s)
		if t.kind == "op" and COMPARISON[t.value] then
			advance(s)
			left = node("binary", t.pos, { op = t.value, left = left, right = parseConcat(s) })
		elseif isKeyword(t, "IS") then
			advance(s)
			local negate = accept(s, "NOT")
			expect(s, "NULL")
			left = node("isnull", t.pos, { expr = left, negate = negate })
		else
			local negate = false
			local save = s.i
			if isKeyword(t, "NOT") then
				advance(s)
				negate = true
			end
			local k = peek(s)
			if isKeyword(k, "LIKE") then
				advance(s)
				left = node("like", k.pos, { expr = left, pattern = parseConcat(s), negate = negate })
			elseif isKeyword(k, "IN") then
				advance(s)
				expectPunct(s, "(")
				local list: { Expr } = {}
				repeat
					table.insert(list, parseExpr(s))
				until not acceptPunct(s, ",")
				expectPunct(s, ")")
				left = node("in", k.pos, { expr = left, list = list, negate = negate })
			elseif isKeyword(k, "BETWEEN") then
				advance(s)
				local low = parseConcat(s)
				expect(s, "AND")
				local high = parseConcat(s)
				left = node("between", k.pos, { expr = left, low = low, high = high, negate = negate })
			else
				s.i = save
				return left
			end
		end
	end
end

local function parseNot(s: State): Expr
	local t = peek(s)
	if isKeyword(t, "NOT") then
		advance(s)
		return node("unary", t.pos, { op = "NOT", operand = parseNot(s) })
	end
	return parseComparison(s)
end

local function parseAnd(s: State): Expr
	local left = parseNot(s)
	while isKeyword(peek(s), "AND") do
		local t = advance(s)
		left = node("binary", t.pos, { op = "AND", left = left, right = parseNot(s) })
	end
	return left
end

parseExpr = function(s: State): Expr
	local left = parseAnd(s)
	while isKeyword(peek(s), "OR") do
		local t = advance(s)
		left = node("binary", t.pos, { op = "OR", left = left, right = parseAnd(s) })
	end
	return left
end

-- Statements --------------------------------------------------------------------

-- A bare word after a name is an alias only if what follows could follow an
-- alias; otherwise it's most likely a misspelled keyword like WHER.
local function bareAlias(s: State): boolean
	if peek(s).kind ~= "ident" then
		return false
	end
	local after = peek(s, 1)
	return after.kind == "eof" or after.kind == "keyword" or after.kind == "punct"
end

local function tableRef(s: State): Ast.TableRef
	local name, pos = identifier(s, "a table name")
	local alias: string? = nil
	if accept(s, "AS") then
		alias = identifier(s, "an alias")
	elseif bareAlias(s) then
		alias = advance(s).value
	elseif peek(s).kind == "ident" then
		fail(s, "unexpected " .. describe(peek(s)) .. " after table " .. name)
	end
	return { name = name, alias = alias, pos = pos }
end

local function parseSelect(s: State, start: Token): Statement
	local stmt: any = { kind = "select", pos = start.pos }
	stmt.distinct = accept(s, "DISTINCT")
	stmt.items = {}
	repeat
		local expr = parseExpr(s)
		local alias: string? = nil
		if accept(s, "AS") then
			alias = identifier(s, "an alias")
		elseif bareAlias(s) then
			alias = advance(s).value
		end
		table.insert(stmt.items, { expr = expr, alias = alias })
	until not acceptPunct(s, ",")

	expect(s, "FROM")
	stmt.from = tableRef(s)
	stmt.joins = {}
	while true do
		local joinType: ("inner" | "left")? = nil
		if accept(s, "JOIN") then
			joinType = "inner"
		elseif accept(s, "INNER") then
			expect(s, "JOIN")
			joinType = "inner"
		elseif accept(s, "LEFT") then
			expect(s, "JOIN")
			joinType = "left"
		end
		if not joinType then
			break
		end
		local target = tableRef(s)
		expect(s, "ON")
		table.insert(stmt.joins, { type = joinType, target = target, on = parseExpr(s) })
	end

	if accept(s, "WHERE") then
		stmt.where = parseExpr(s)
	end
	if accept(s, "GROUP") then
		expect(s, "BY")
		stmt.groupBy = {}
		repeat
			table.insert(stmt.groupBy, parseExpr(s))
		until not acceptPunct(s, ",")
	end
	if accept(s, "HAVING") then
		stmt.having = parseExpr(s)
	end
	if accept(s, "ORDER") then
		expect(s, "BY")
		stmt.orderBy = {}
		repeat
			local expr = parseExpr(s)
			local desc = false
			if accept(s, "DESC") then
				desc = true
			else
				accept(s, "ASC")
			end
			table.insert(stmt.orderBy, { expr = expr, desc = desc })
		until not acceptPunct(s, ",")
	end
	if accept(s, "LIMIT") then
		stmt.limit = parseExpr(s)
		if accept(s, "OFFSET") then
			stmt.offset = parseExpr(s)
		elseif acceptPunct(s, ",") then
			-- MySQL style LIMIT offset, count
			stmt.offset = stmt.limit
			stmt.limit = parseExpr(s)
		end
	end
	return stmt :: Statement
end

local function parseInsert(s: State, start: Token): Statement
	expect(s, "INTO")
	local stmt: any = { kind = "insert", pos = start.pos }
	stmt.table, stmt.pos = identifier(s, "a table name")
	if acceptPunct(s, "(") then
		stmt.columns = {}
		repeat
			table.insert(stmt.columns, (identifier(s, "a column name")))
		until not acceptPunct(s, ",")
		expectPunct(s, ")")
	end
	expect(s, "VALUES")
	stmt.rows = {}
	repeat
		expectPunct(s, "(")
		local row: { Expr } = {}
		repeat
			table.insert(row, parseExpr(s))
		until not acceptPunct(s, ",")
		expectPunct(s, ")")
		table.insert(stmt.rows, row)
	until not acceptPunct(s, ",")
	return stmt :: Statement
end

local function parseUpdate(s: State, start: Token): Statement
	local stmt: any = { kind = "update", pos = start.pos }
	stmt.table, stmt.pos = identifier(s, "a table name")
	expect(s, "SET")
	stmt.sets = {}
	repeat
		local column, pos = identifier(s, "a column name")
		if not acceptOp(s, "=") then
			fail(s, "expected '=' after column " .. column)
		end
		table.insert(stmt.sets, { column = column, expr = parseExpr(s), pos = pos })
	until not acceptPunct(s, ",")
	if accept(s, "WHERE") then
		stmt.where = parseExpr(s)
	end
	return stmt :: Statement
end

local function parseDelete(s: State, start: Token): Statement
	expect(s, "FROM")
	local stmt: any = { kind = "delete", pos = start.pos }
	stmt.table, stmt.pos = identifier(s, "a table name")
	if accept(s, "WHERE") then
		stmt.where = parseExpr(s)
	end
	return stmt :: Statement
end

local function parseColumnDef(s: State): Ast.ColumnDef
	local name, pos = identifier(s, "a column name")
	local def: Ast.ColumnDef = {
		name = name,
		type = "ANY",
		primaryKey = false,
		autoincrement = false,
		notNull = false,
		unique = false,
		default = nil,
		pos = pos,
	}
	-- optional type name, possibly with a size: VARCHAR(32)
	local t = peek(s)
	if t.kind == "ident" then
		def.type = string.upper(advance(s).value)
		if acceptPunct(s, "(") then
			repeat
				advance(s)
			until not acceptPunct(s, ",")
			expectPunct(s, ")")
		end
	end
	while true do
		if accept(s, "PRIMARY") then
			expect(s, "KEY")
			def.primaryKey = true
		elseif accept(s, "AUTOINCREMENT") then
			def.autoincrement = true
		elseif accept(s, "NOT") then
			expect(s, "NULL")
			def.notNull = true
		elseif accept(s, "NULL") then
			def.notNull = false
		elseif accept(s, "UNIQUE") then
			def.unique = true
		elseif accept(s, "DEFAULT") then
			def.default = parseUnary(s)
		else
			break
		end
	end
	return def
end

local function parseCreate(s: State, start: Token): Statement
	expect(s, "TABLE")
	local stmt: any = { kind = "create", pos = start.pos }
	if accept(s, "IF") then
		expect(s, "NOT")
		expect(s, "EXISTS")
		stmt.ifNotExists = true
	end
	stmt.table = identifier(s, "a table name")
	expectPunct(s, "(")
	stmt.columnDefs = {}
	repeat
		if accept(s, "PRIMARY") then
			-- table-level PRIMARY KEY (column)
			expect(s, "KEY")
			expectPunct(s, "(")
			local column, pos = identifier(s, "a column name")
			expectPunct(s, ")")
			local found = false
			for _, def in stmt.columnDefs do
				if def.name == column then
					def.primaryKey = true
					found = true
				end
			end
			if not found then
				Errors.raise("semantic", "PRIMARY KEY names unknown column " .. column, pos, s.query)
			end
		else
			table.insert(stmt.columnDefs, parseColumnDef(s))
		end
	until not acceptPunct(s, ",")
	expectPunct(s, ")")
	return stmt :: Statement
end

local function parseAlter(s: State, start: Token): Statement
	expect(s, "TABLE")
	local stmt: any = { kind = "alter", pos = start.pos }
	stmt.table, stmt.pos = identifier(s, "a table name")
	if accept(s, "ADD") then
		accept(s, "COLUMN")
		stmt.action = "add"
		stmt.columnDef = parseColumnDef(s)
	elseif accept(s, "DROP") then
		accept(s, "COLUMN")
		stmt.action = "drop"
		stmt.column = identifier(s, "a column name")
	elseif accept(s, "RENAME") then
		accept(s, "COLUMN")
		stmt.action = "rename"
		stmt.column = identifier(s, "a column name")
		expect(s, "TO")
		stmt.newName = identifier(s, "the new column name")
	else
		fail(s, "expected ADD, DROP or RENAME after ALTER TABLE " .. stmt.table)
	end
	return stmt :: Statement
end

local function parseStatement(s: State): Statement
	local t = advance(s)
	if isKeyword(t, "SELECT") then
		return parseSelect(s, t)
	elseif isKeyword(t, "INSERT") then
		return parseInsert(s, t)
	elseif isKeyword(t, "UPDATE") then
		return parseUpdate(s, t)
	elseif isKeyword(t, "DELETE") then
		return parseDelete(s, t)
	elseif isKeyword(t, "CREATE") then
		return parseCreate(s, t)
	elseif isKeyword(t, "DROP") then
		expect(s, "TABLE")
		local stmt: any = { kind = "drop", pos = t.pos }
		if accept(s, "IF") then
			expect(s, "EXISTS")
			stmt.ifExists = true
		end
		stmt.table, stmt.pos = identifier(s, "a table name")
		return stmt
	elseif isKeyword(t, "TRUNCATE") then
		accept(s, "TABLE")
		local name, pos = identifier(s, "a table name")
		return { kind = "truncate", pos = pos, table = name } :: any
	elseif isKeyword(t, "ALTER") then
		return parseAlter(s, t)
	elseif isKeyword(t, "EXPLAIN") then
		local inner = parseStatement(s)
		if inner.kind ~= "select" and inner.kind ~= "update" and inner.kind ~= "delete" then
			Errors.raise("syntax", "EXPLAIN works with SELECT, UPDATE and DELETE", t.pos, s.query)
		end
		return { kind = "explain", pos = t.pos, statement = inner } :: any
	elseif isKeyword(t, "SHOW") then
		expect(s, "TABLES")
		return { kind = "showTables", pos = t.pos } :: any
	elseif isKeyword(t, "DESCRIBE") then
		local name, pos = identifier(s, "a table name")
		return { kind = "describe", pos = pos, table = name } :: any
	end
	return fail(
		s,
		"expected a statement (SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, TRUNCATE, ALTER, ...), got " .. describe(t),
		t
	)
end

function Parser.parse(query: string): Statement
	if type(query) ~= "string" then
		error("rSQL: query must be a string, got " .. typeof(query), 0)
	end
	local s: State = { tokens = Lexer.tokenize(query), i = 1, query = query, positional = 0 }
	local stmt = parseStatement(s)
	acceptPunct(s, ";")
	local rest = peek(s)
	if rest.kind ~= "eof" then
		fail(s, "unexpected " .. describe(rest) .. " after the end of the statement", rest)
	end
	stmt.paramCount = s.positional
	return stmt
end

return Parser
