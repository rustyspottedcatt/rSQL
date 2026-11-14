--[[
	Benchmarks (Lune). Writes docs/figures/data/bench.json and prints a table.

	    lune run bench/run

	DataStore numbers come from tests/support/FakeDataStore, which counts
	requests and the size of what each request returns (JSON bytes, close to
	what Roblox serializes). Times are Lune-on-a-laptop times; on a server the
	DataStore round trips dominate, which is why requests and bytes matter more.
]]

local fs = require("@lune/fs")
local rSQL = require("../src")
local Json = require("../src/Util/Json")
local FakeDataStore = require("../tests/support/FakeDataStore")

local SIZES = { 100, 500, 1000, 2500, 5000 }
local results =
	{ generatedWith = "lune run bench/run", lookup = {}, operations = {}, shardRows = {}, parse = {}, memory = {} }

local function noSleep() end

local function fill(db, n: number)
	db:exec(
		"CREATE TABLE Players (UserId INTEGER PRIMARY KEY, Name TEXT NOT NULL, Team TEXT, Coins INTEGER DEFAULT 0, Level INTEGER DEFAULT 1)"
	)
	local batch = {}
	local params = {}
	for i = 1, n do
		table.insert(batch, "(?, ?, ?, ?, ?)")
		for _, v in
			{
				i,
				"player_" .. i,
				if i % 3 == 0 then "red" elseif i % 3 == 1 then "blue" else "green",
				i * 7 % 1000,
				i % 50 + 1,
			}
		do
			table.insert(params, v)
		end
		if #batch == 100 or i == n then
			params.n = #params
			db:exec(
				"INSERT INTO Players (UserId, Name, Team, Coins, Level) VALUES " .. table.concat(batch, ", "),
				params
			)
			batch, params = {}, {}
		end
	end
end

local function median(samples: { number }): number
	table.sort(samples)
	return samples[(#samples + 1) // 2]
end

-- 1. key lookup cost as tables grow: 1.x single-key layout vs sharded
print("key lookups by table size")
for _, n in SIZES do
	local row = { rows = n }
	for _, layout in { "single", "sharded" } do
		local store = FakeDataStore.new({ limitBytes = math.huge })
		local db = rSQL.datastore(store, { layout = layout, shards = 8, sleep = noSleep })
		fill(db, n)
		store:reset()
		local times = {}
		local lookups = 20
		for k = 1, lookups do
			local t0 = os.clock()
			db:exec("SELECT Name, Coins FROM Players WHERE UserId = ?", { (k * 37) % n + 1 })
			times[k] = os.clock() - t0
		end
		row[layout] = {
			requests = (store.requests.get + store.requests.update) / lookups,
			bytes = store.bytesRead / lookups,
			ms = median(times) * 1000,
		}
		if layout == "single" then
			local size = #Json.encode(store.data.Players)
			row.tableBytes = size
		end
	end
	table.insert(results.lookup, row)
	print(
		string.format(
			"  %5d rows  table %7.1f KB | 1.x layout %7.1f KB/lookup | sharded %6.1f KB/lookup",
			n,
			row.tableBytes / 1024,
			row.single.bytes / 1024,
			row.sharded.bytes / 1024
		)
	)
end

-- 2. requests per statement on a sharded table
do
	local store = FakeDataStore.new()
	local db = rSQL.datastore(store, { shards = 8, sleep = noSleep })
	fill(db, 1000)
	local function measure(label: string, sql: string, params: { any }?)
		store:reset()
		db:exec(sql, params)
		table.insert(results.operations, {
			label = label,
			reads = store.requests.get,
			writes = store.requests.update + store.requests.remove + store.requests.set,
		})
	end
	measure("SELECT by key", "SELECT * FROM Players WHERE UserId = 42")
	measure("UPDATE by key", "UPDATE Players SET Coins = Coins + 1 WHERE UserId = 42")
	measure("INSERT one row", "INSERT INTO Players (UserId, Name) VALUES (5001, 'new')")
	measure("DELETE by key", "DELETE FROM Players WHERE UserId = 5001")
	measure("SELECT with filter", "SELECT * FROM Players WHERE Coins > 900")
	measure("UPDATE with filter", "UPDATE Players SET Level = Level + 1 WHERE Team = 'red'")
	print("\nrequests per statement (1,000 rows, 8 shards)")
	for _, op in results.operations do
		print(string.format("  %-20s %d reads, %d writes", op.label, op.reads, op.writes))
	end

	-- 3. how evenly rows land on shards
	local meta = store.data["Players/meta"]
	for i = 1, meta.shards do
		local count = 0
		for _ in store.data["Players/1." .. i].rows do
			count += 1
		end
		results.shardRows[i] = count
	end
	print("\nrows per shard: " .. table.concat(results.shardRows, ", "))
end

-- 4. parsing, with and without the statement cache
do
	local sql = "SELECT Name, Coins FROM Players WHERE Team = ? AND Coins BETWEEN ? AND ? ORDER BY Coins DESC LIMIT 10"
	local n = 5000
	local t0 = os.clock()
	for _ = 1, n do
		rSQL.parse(sql)
	end
	local cold = os.clock() - t0
	local db = rSQL.memory()
	fill(db, 10)
	local stmt = db:prepare(sql)
	t0 = os.clock()
	for _ = 1, n do
		stmt:run({ "red", 0, 1000 })
	end
	local warm = os.clock() - t0
	results.parse = { parsePerSecond = n / cold, cachedQueriesPerSecond = n / warm }
	print(string.format("\nparse: %.0f statements/s; cached statement on 10 rows: %.0f queries/s", n / cold, n / warm))
end

-- 5. in-memory lookups vs scans
do
	local db = rSQL.memory()
	fill(db, 10000)
	local lookups, scans = {}, {}
	for k = 1, 21 do
		local t0 = os.clock()
		db:exec("SELECT * FROM Players WHERE UserId = ?", { k * 400 })
		lookups[k] = os.clock() - t0
		t0 = os.clock()
		db:exec("SELECT * FROM Players WHERE Name = ?", { "player_" .. (k * 400) })
		scans[k] = os.clock() - t0
	end
	results.memory = { rows = 10000, lookupMs = median(lookups) * 1000, scanMs = median(scans) * 1000 }
	print(
		string.format(
			"\nin-memory, 10,000 rows: key lookup %.3f ms, filter scan %.2f ms",
			results.memory.lookupMs,
			results.memory.scanMs
		)
	)
end

if not fs.isDir("docs/figures/data") then
	fs.writeDir("docs/figures/data")
end
fs.writeFile("docs/figures/data/bench.json", Json.encode(results))
print("\nwrote docs/figures/data/bench.json")
