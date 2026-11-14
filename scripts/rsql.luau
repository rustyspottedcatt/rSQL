--[[
	Interactive SQL shell for trying rSQL outside Roblox.

	    lune run scripts/rsql                         # in-memory, gone on exit
	    lune run scripts/rsql -- --store dev.json      # a fake DataStore saved to dev.json
	    lune run scripts/rsql -- --file seed.sql       # run a file of statements, then exit

	Shell commands start with a dot: .tables  .schema <table>  .explain <query>
	.stats  .help  .quit. Everything else is SQL; end a statement with ;
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local rSQL = require("../src")
local Json = require("../src/Util/Json")
local FakeDataStore = require("../tests/support/FakeDataStore")

local flags: { [string]: string } = {}
do
	local i = 1
	while i <= #process.args do
		local a = process.args[i]
		if string.sub(a, 1, 2) == "--" and a ~= "--" then
			flags[string.sub(a, 3)] = process.args[i + 1] or ""
			i += 2
		else
			i += 1
		end
	end
end

local storePath = flags.store
local store = FakeDataStore.new()
if storePath and fs.isFile(storePath) then
	store.data = Json.decode(fs.readFile(storePath))
end
local db = if storePath then rSQL.datastore(store, { sleep = function() end }) else rSQL.memory()

local function save()
	if storePath then
		fs.writeFile(storePath, Json.encode(store.data))
	end
end

local function cell(v: any): string
	if v == nil then
		return "NULL"
	elseif typeof(v) == "table" then
		return Json.encode(v)
	end
	return tostring(v)
end

-- Draws result rows as a box table.
local function render(columns: { string }, rows: { { [string]: any } }): string
	local widths = {}
	for i, c in columns do
		widths[i] = utf8.len(c) or #c
		for _, row in rows do
			local text = cell(row[c])
			widths[i] = math.max(widths[i], utf8.len(text) or #text)
		end
	end
	local function line(left: string, mid: string, right: string): string
		local parts = {}
		for i in columns do
			parts[i] = string.rep("─", widths[i] + 2)
		end
		return left .. table.concat(parts, mid) .. right
	end
	local function rowText(values: { string }): string
		local parts = {}
		for i, v in values do
			parts[i] = " " .. v .. string.rep(" ", widths[i] - (utf8.len(v) or #v)) .. " "
		end
		return "│" .. table.concat(parts, "│") .. "│"
	end
	local out = { line("┌", "┬", "┐"), rowText(columns), line("├", "┼", "┤") }
	for _, row in rows do
		local values = {}
		for i, c in columns do
			values[i] = cell(row[c])
		end
		table.insert(out, rowText(values))
	end
	table.insert(out, line("└", "┴", "┘"))
	return table.concat(out, "\n")
end

local function run(sql: string)
	local ok, result = pcall(db.exec, db, sql)
	if not ok then
		print(stdio.color("red") .. tostring(result) .. stdio.color("reset"))
		return
	end
	if #result.columns > 0 then
		print(render(result.columns, result.rows))
		print(
			string.format(
				"%s%d row%s · %s · %d reads · %.2f ms%s",
				stdio.color("blue"),
				#result.rows,
				if #result.rows == 1 then "" else "s",
				(result.plan and result.plan[1]) or result.kind,
				result.stats.reads,
				result.stats.ms,
				stdio.color("reset")
			)
		)
	else
		print(stdio.color("green") .. (result.message or "ok") .. stdio.color("reset"))
	end
	save()
end

local function command(line: string): boolean
	local name, rest = string.match(line, "^%.(%w+)%s*(.-)%s*;?$")
	if name == "quit" or name == "exit" then
		return false
	elseif name == "tables" then
		run("SHOW TABLES")
	elseif name == "schema" then
		run("DESCRIBE " .. (rest or ""))
	elseif name == "explain" then
		run("EXPLAIN " .. (rest or ""))
	elseif name == "stats" then
		local s = db.stats
		print(
			string.format(
				"%d queries, %d reads, %d writes, %.1f ms, %d parse-cache hits",
				s.queries,
				s.reads,
				s.writes,
				s.ms,
				s.cacheHits
			)
		)
	else
		print(".tables  .schema <table>  .explain <query>  .stats  .quit")
	end
	return true
end

if flags.file then
	local text = fs.readFile(flags.file)
	-- statements end at ; (strings with ; inside aren't split)
	local buffer, inString = {}, nil
	for i = 1, #text do
		local c = string.sub(text, i, i)
		table.insert(buffer, c)
		if inString then
			if c == inString then
				inString = nil
			end
		elseif c == "'" or c == '"' then
			inString = c
		elseif c == ";" then
			local sql = string.match(table.concat(buffer), "^%s*(.-)%s*$") :: string
			buffer = {}
			if #sql > 1 then
				print(stdio.color("cyan") .. "rsql> " .. stdio.color("reset") .. sql)
				run(sql)
			end
		end
	end
	process.exit(0)
end

print(string.format("rSQL %s · %s · .help for commands", rSQL.version, if storePath then storePath else "in-memory"))
local pending = {}
local piped = false
while true do
	local promptText = if #pending == 0 then "rsql>" else "  ...>"
	local line: string?
	if not piped then
		local ok, value = pcall(stdio.prompt, "text", promptText)
		if ok then
			line = value
		else
			piped = true
		end
	end
	if piped then
		line = stdio.readLine()
		if line then
			line = string.gsub(line, "[\r\n]+$", "")
		end
	end
	if line == nil then
		break
	end
	local text = line :: string
	if #pending == 0 and string.sub(text, 1, 1) == "." then
		if not command(text) then
			break
		end
	elseif #text > 0 then
		table.insert(pending, text)
		if string.find(text, ";%s*$") then
			run(table.concat(pending, "\n"))
			pending = {}
		end
	end
end
