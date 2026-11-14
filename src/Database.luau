--!strict
--[[
	A database handle: what `rSQL.open`, `rSQL.memory` and friends return.

	    local result = db:exec("SELECT Name FROM Players WHERE UserId = ?", { userId })
	    print(result.rows[1].Name)

	exec runs on the calling thread (DataStore calls yield as usual) and
	raises on error. query does the same work but returns a promise, for
	code written in the 1.x style.

	Parsed statements are cached by their SQL text, so running the same
	query with different parameters only parses it once.
]]

local Parser = require("./SQL/Parser")
local Ast = require("./SQL/Ast")
local Executor = require("./Engine/Executor")
local Expression = require("./Engine/Expression")
local Adapter = require("./Storage/Adapter")
local Permissions = require("./Permissions")
local Promise = require("./Promise")
local Platform = require("./Platform")
local Logger = require("./Util/Logger")

export type Result = Executor.Result & {
	stats: { ms: number, reads: number, writes: number },
}

export type QueryInfo = {
	sql: string,
	kind: string,
	ms: number,
	reads: number,
	writes: number,
	rows: number,
	ok: boolean,
	error: string?,
}

export type Options = {
	permissions: any?,
	cacheSize: number?,
	createIsNoop: boolean?,
	firstColumnKey: boolean?,
	createOptions: Adapter.CreateOptions?,
	logger: Logger.Logger?,
	onQuery: ((info: QueryInfo) -> ())?,
}

export type Statement = {
	sql: string,
	kind: string,
	run: (self: Statement, params: { [any]: any }?) -> Result,
}

export type Database = {
	adapter: Adapter.Adapter,
	stats: { queries: number, reads: number, writes: number, ms: number, cacheHits: number },
	exec: (self: Database, sql: string, params: { [any]: any }?) -> Result,
	query: (self: Database, sql: string, params: { [any]: any }?) -> any,
	prepare: (self: Database, sql: string) -> Statement,
	explain: (self: Database, sql: string) -> { string },
	tables: (self: Database) -> { string },
	reshard: (self: Database, tableName: string, shards: number) -> (),
}

local Database = {}

function Database.new(adapter: Adapter.Adapter, options: Options?): Database
	local opts: Options = options or {}
	local permissions = Permissions.resolve(opts.permissions)
	local cacheSize = opts.cacheSize or 128
	local logger = opts.logger or Logger.new({ scope = "rSQL" })
	local executorOptions: Executor.Options = {
		createIsNoop = opts.createIsNoop,
		firstColumnKey = opts.firstColumnKey,
		createOptions = opts.createOptions,
		warn = function(message)
			logger:warn("%s", message)
		end,
	}

	local self = {
		adapter = adapter,
		stats = { queries = 0, reads = 0, writes = 0, ms = 0, cacheHits = 0 },
	} :: Database

	-- small LRU of parsed statements
	local cache: { [string]: { stmt: Ast.Statement, used: number } } = {}
	local cached = 0
	local clock = 0
	local function parse(sql: string): Ast.Statement
		clock += 1
		local entry = cache[sql]
		if entry then
			entry.used = clock
			self.stats.cacheHits += 1
			return entry.stmt
		end
		local stmt = Parser.parse(sql)
		if cached >= cacheSize then
			local oldest, oldestUse = nil, math.huge
			for key, e in cache do
				if e.used < oldestUse then
					oldest, oldestUse = key, e.used
				end
			end
			if oldest then
				cache[oldest] = nil
				cached -= 1
			end
		end
		cache[sql] = { stmt = stmt, used = clock }
		cached += 1
		return stmt
	end

	local function run(sql: string, stmt: Ast.Statement, params: { [any]: any }?): Result
		local required = Permissions.required(stmt.kind)
		local inner = if stmt.kind == "explain" then (stmt.statement :: Ast.Statement).kind else stmt.kind
		if not permissions[required] or not permissions[Permissions.required(inner)] then
			error(string.format("rSQL: %s isn't allowed on this database handle", string.upper(inner)), 0)
		end
		local started = Platform.clock()
		local reads, writes = adapter.stats.reads, adapter.stats.writes
		local scoped = adapter :: any
		if scoped.beginStatement then
			scoped:beginStatement()
		end
		local ok, resultOrError = pcall(Executor.execute, adapter, stmt, params or {}, sql, executorOptions)
		if scoped.endStatement then
			scoped:endStatement()
		end
		local ms = (Platform.clock() - started) * 1000
		local dr, dw = adapter.stats.reads - reads, adapter.stats.writes - writes
		self.stats.queries += 1
		self.stats.reads += dr
		self.stats.writes += dw
		self.stats.ms += ms
		if opts.onQuery then
			opts.onQuery({
				sql = sql,
				kind = stmt.kind,
				ms = ms,
				reads = dr,
				writes = dw,
				rows = if ok then #resultOrError.rows else 0,
				ok = ok,
				error = if ok then nil else tostring(resultOrError),
			})
		end
		if not ok then
			error(resultOrError, 0)
		end
		local result = resultOrError :: any
		result.stats = { ms = ms, reads = dr, writes = dw }
		return result
	end

	function self:exec(sql: string, params: { [any]: any }?): Result
		return run(sql, parse(sql), params)
	end

	function self:query(sql: string, params: { [any]: any }?): any
		return Promise.new(function(resolve)
			resolve(self:exec(sql, params))
		end)
	end

	function self:prepare(sql: string): Statement
		local stmt = parse(sql)
		local statement = { sql = sql, kind = stmt.kind } :: Statement
		function statement:run(params: { [any]: any }?): Result
			return run(sql, stmt, params)
		end
		return statement
	end

	function self:explain(sql: string): { string }
		local stmt = parse(sql)
		if stmt.kind ~= "explain" then
			stmt = Parser.parse("EXPLAIN " .. sql)
		end
		return run(sql, stmt, nil).plan or {}
	end

	function self:tables(): { string }
		return adapter:listTables()
	end

	function self:reshard(tableName: string, shards: number)
		local fn = (adapter :: any).reshard
		if not fn then
			error("rSQL: resharding only applies to DataStore databases", 0)
		end
		if not permissions.alter then
			error("rSQL: resharding needs the alter permission", 0)
		end
		fn(adapter, tableName, shards)
	end

	return self
end

Database.NULL = Expression.NULL

return Database
