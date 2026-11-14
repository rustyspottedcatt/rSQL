local rSQL = require("../../src")
local FakeDataStore = require("../support/FakeDataStore")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	local function noSleep() end

	local function players(db)
		db:exec("CREATE TABLE Players (UserId INTEGER PRIMARY KEY, Name TEXT, Coins INTEGER DEFAULT 0)")
		for i = 1, 40 do
			db:exec("INSERT INTO Players (UserId, Name, Coins) VALUES (?, ?, ?)", { i, "p" .. i, i * 10 })
		end
	end

	describe("DataStore (sharded)", function()
		it("stores tables as a meta key plus one key per shard", function()
			local store = FakeDataStore.new()
			local db = rSQL.datastore(store, { shards = 4, sleep = noSleep })
			players(db)
			expect(store.data["Players/meta"].shards).toBe(4)
			local total = 0
			for i = 1, 4 do
				local shard = store.data["Players/1." .. i]
				expect(shard ~= nil).toBe(true)
				for _ in shard.rows do
					total += 1
				end
			end
			expect(total).toBe(40)
			expect(store.data.__rsql_tables).toEqual({ "Players" })
		end)

		it("reads one shard for a key lookup and all of them for a scan", function()
			local store = FakeDataStore.new()
			local db = rSQL.datastore(store, { shards = 8, sleep = noSleep })
			players(db)
			store:reset()
			local r = db:exec("SELECT Name FROM Players WHERE UserId = 17")
			expect(r.rows[1].Name).toBe("p17")
			expect(store.requests.get).toBe(2) -- meta + one shard
			store:reset()
			db:exec("SELECT COUNT(*) AS n FROM Players WHERE Coins > 100")
			expect(store.requests.get).toBe(9) -- meta + 8 shards
		end)

		it("writes only the shard a keyed update touches", function()
			local store = FakeDataStore.new()
			local db = rSQL.datastore(store, { shards = 8, sleep = noSleep })
			players(db)
			store:reset()
			db:exec("UPDATE Players SET Coins = Coins + 5 WHERE UserId = 3")
			expect(store.requests.update).toBe(1)
			expect(db:exec("SELECT Coins FROM Players WHERE UserId = 3").rows[1].Coins).toBe(35)
		end)

		it("gives the same answers as the in-memory engine", function()
			local mem, ds = rSQL.memory(), rSQL.datastore(FakeDataStore.new(), { shards = 3, sleep = noSleep })
			for _, db in { mem, ds } do
				players(db)
				db:exec("UPDATE Players SET Name = 'vip' WHERE Coins >= 300")
				db:exec("DELETE FROM Players WHERE UserId % 7 = 0")
			end
			for _, q in
				{
					"SELECT * FROM Players ORDER BY UserId",
					"SELECT Name, COUNT(*) AS n, SUM(Coins) AS s FROM Players GROUP BY Name ORDER BY Name",
					"SELECT UserId FROM Players WHERE UserId IN (1, 7, 14, 20) ORDER BY UserId",
				}
			do
				expect(ds:exec(q).rows).toEqual(mem:exec(q).rows)
			end
		end)

		it("keeps writes from two servers on different shards", function()
			local store = FakeDataStore.new()
			local a = rSQL.datastore(store, { shards = 8, sleep = noSleep })
			local b = rSQL.datastore(store, { shards = 8, sleep = noSleep })
			a:exec("CREATE TABLE Players (UserId INTEGER PRIMARY KEY, Coins INTEGER)")
			for i = 1, 20 do
				local db = if i % 2 == 0 then a else b
				db:exec("INSERT INTO Players VALUES (?, 0)", { i })
			end
			expect(a:exec("SELECT COUNT(*) AS n FROM Players").rows[1].n).toBe(20)
		end)

		it("retries throttled requests with back-off", function()
			local store = FakeDataStore.new()
			local sleeps = {}
			local db = rSQL.datastore(store, {
				sleep = function(s)
					table.insert(sleeps, s)
				end,
			})
			db:exec("CREATE TABLE T (Id INTEGER PRIMARY KEY)")
			store:failNext(2)
			db:exec("INSERT INTO T VALUES (1)")
			expect(sleeps).toEqual({ 0.5, 1 })
			expect(#db:exec("SELECT * FROM T").rows).toBe(1)
		end)

		it("gives up after the retry limit with the DataStore error", function()
			local store = FakeDataStore.new()
			local db = rSQL.datastore(store, { retries = 1, sleep = noSleep })
			db:exec("CREATE TABLE T (Id INTEGER PRIMARY KEY)")
			store:failNext(5)
			expect(function()
				db:exec("INSERT INTO T VALUES (1)")
			end).toThrow("failed after 2 attempts")
		end)

		it("explains the size limit instead of a raw DataStore error", function()
			local store = FakeDataStore.new({ limitBytes = 2000 })
			local db = rSQL.datastore(store, { shards = 1, sleep = noSleep })
			db:exec("CREATE TABLE Notes (Id INTEGER PRIMARY KEY, Body TEXT)")
			expect(function()
				db:exec("INSERT INTO Notes VALUES (1, ?)", { string.rep("x", 5000) })
			end).toThrow("size limit")
		end)

		it("reshards a table without losing rows", function()
			local store = FakeDataStore.new()
			local db = rSQL.datastore(store, { shards = 2, sleep = noSleep })
			players(db)
			db:reshard("Players", 16)
			expect(store.data["Players/meta"].shards).toBe(16)
			expect(store.data["Players/1.1"]).toBeNil()
			expect(db:exec("SELECT COUNT(*) AS n FROM Players").rows[1].n).toBe(40)
			expect(db:exec("SELECT Name FROM Players WHERE UserId = 33").rows[1].Name).toBe("p33")
		end)

		it("refuses names that won't fit in a DataStore key", function()
			local db = rSQL.datastore(FakeDataStore.new(), { prefix = "season3_live_", sleep = noSleep })
			expect(function()
				db:exec("CREATE TABLE " .. string.rep("a", 30) .. " (Id INTEGER)")
			end).toThrow("too long")
		end)

		it("doesn't move rows between shards by changing their key", function()
			local db = rSQL.datastore(FakeDataStore.new(), { sleep = noSleep })
			players(db)
			expect(function()
				db:exec("UPDATE Players SET UserId = 999 WHERE UserId = 1")
			end).toThrow("primary key")
		end)
	end)

	describe("DataStore (single key, 1.x compatible)", function()
		it("writes the 1.x layout", function()
			local store = FakeDataStore.new()
			local db = rSQL.datastore(store, { layout = "single", sleep = noSleep })
			db:exec("CREATE TABLE Players (ID INTEGER PRIMARY KEY, Name TEXT)")
			db:exec("INSERT INTO Players VALUES (1, 'alice')")
			local value = store.data.Players
			expect(value._schema).toEqual({ "ID", "Name" })
			expect(value.rows).toEqual({ { ID = 1, Name = "alice" } })
		end)

		it("reads and writes tables created by 1.x", function()
			local store = FakeDataStore.new()
			-- what rSQL 1.x left in the DataStore: strings everywhere, first column as key
			store.data.Players = {
				_schema = { "ID", "Name", "Score" },
				rows = { { ID = "1", Name = "Alice", Score = "500" }, { ID = "2", Name = "Bob", Score = "90" } },
			}
			local db = rSQL.datastore(store, { sleep = noSleep })
			local r = db:exec("SELECT Name FROM Players WHERE Score > 100")
			expect(r.rows[1].Name).toBe("Alice")
			db:exec("UPDATE Players SET Score = Score + 1 WHERE ID = 2")
			expect(db:exec("SELECT Score FROM Players WHERE ID = 2").rows[1].Score).toBe(91)
			expect(function()
				db:exec("INSERT INTO Players (ID, Name, Score) VALUES ('1', 'dup', '0')")
			end).toThrow("duplicate key")
		end)

		it("moves a 1.x table to the sharded layout", function()
			local store = FakeDataStore.new()
			store.data.Players = { _schema = { "ID", "Name" }, rows = { { ID = "1", Name = "Alice" } } }
			local db = rSQL.datastore(store, { sleep = noSleep })
			db:reshard("Players", 4)
			expect(store.data.Players).toBeNil()
			expect(db:exec("SELECT Name FROM Players WHERE ID = '1'").rows[1].Name).toBe("Alice")
		end)
	end)

	describe("Profiles", function()
		it("stores tables inside profile.Data in the 1.x layout", function()
			local profile = { Data = { Coins = 10 } }
			local db = rSQL.profile(profile)
			db:exec("CREATE TABLE Inventory (Item TEXT PRIMARY KEY, Count INTEGER DEFAULT 1)")
			db:exec("INSERT INTO Inventory (Item) VALUES ('apple'), ('sword')")
			db:exec("UPDATE Inventory SET Count = Count + 2 WHERE Item = 'apple'")
			expect(profile.Data.Coins).toBe(10)
			expect(profile.Data.Inventory._schema).toEqual({ "Item", "Count" })
			expect(profile.Data.Inventory.rows[1]).toEqual({ Item = "apple", Count = 3 })
		end)

		it("reads profile tables written by 1.x", function()
			local profile =
				{ Data = { Quests = { _schema = { "Id", "Done" }, rows = { { Id = "q1", Done = "true" } } } } }
			local db = rSQL.profile(profile)
			expect(db:exec("SELECT Done FROM Quests WHERE Id = 'q1'").rows[1].Done).toBe("true")
		end)

		it("accepts a bare data table too", function()
			local data = {}
			rSQL.profile(data):exec("CREATE TABLE T (Id INTEGER PRIMARY KEY)")
			expect(data.T ~= nil).toBe(true)
		end)
	end)

	describe("In-memory", function()
		it("serves item and loot tables with indexed lookups", function()
			local loot = rSQL.memory()
			loot:exec("CREATE TABLE Loot (Id INTEGER PRIMARY KEY, Item TEXT, Rarity TEXT, Weight REAL)")
			loot:exec([[INSERT INTO Loot VALUES (1, 'Wooden Sword', 'common', 60),
				(2, 'Fire Staff', 'rare', 9.5), (3, 'Ice Staff', 'rare', 10), (4, 'Dragon Egg', 'legendary', 0.5)]])
			local rare =
				loot:exec("SELECT Item FROM Loot WHERE Rarity = 'rare' AND Item LIKE '%staff' ORDER BY Weight DESC")
			expect(#rare.rows).toBe(2)
			expect(rare.rows[1].Item).toBe("Ice Staff")
			expect(loot:exec("SELECT SUM(Weight) AS w FROM Loot").rows[1].w).toBe(80)
		end)
	end)
end
