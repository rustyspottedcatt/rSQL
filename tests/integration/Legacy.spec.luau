local rSQL = require("../../src")
local Promise = require("../../src/Promise")
local FakeDataStore = require("../support/FakeDataStore")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	local ALL = {
		allowCreate = true,
		allowInsert = true,
		allowSelect = true,
		allowUpdate = true,
		allowDelete = true,
		allowDrop = true,
		allowTruncate = true,
		allowAlter = true,
	}

	describe("1.x API", function()
		it("connects with a promise and runs queries through promises", function()
			local conn = rSQL:connect(FakeDataStore.new(), ALL):expect()
			local rows = conn:query("CREATE TABLE PlayerData (id, name, score)")
				:andThen(function()
					return conn:query("INSERT INTO PlayerData (id, name, score) VALUES ('1', 'Alice', '500')")
				end)
				:andThen(function()
					return conn:query("SELECT * FROM PlayerData WHERE id = '1'")
				end)
				:expect()
			expect(rows).toEqual({ { id = "1", name = "Alice", score = "500" } })
		end)

		it("rejects with a message instead of throwing", function()
			local conn = rSQL:connect(FakeDataStore.new(), ALL):expect()
			local caught
			conn:query("SELEC broken"):catch(function(err)
				caught = err
			end)
			expect(caught).toContain("did you mean SELECT?")
		end)

		it("keeps data when the quick-start script runs CREATE TABLE on every boot", function()
			local store = FakeDataStore.new()
			local function boot()
				local conn = rSQL:connect(store, ALL):expect()
				conn:query("CREATE TABLE Players (ID, Name, Score)"):expect()
				return conn
			end
			local first = boot()
			first:query("INSERT INTO Players (ID, Name, Score) VALUES (1, 'alice', 10)"):expect()
			local second = boot() -- 1.x wiped the table here
			expect(#second:query("SELECT * FROM Players"):expect()).toBe(1)
		end)

		it("stores tables in the 1.x single-key layout", function()
			local store = FakeDataStore.new()
			local conn = rSQL:connect(store, ALL):expect()
			conn:query("CREATE TABLE Players (ID, Name)"):expect()
			conn:query("INSERT INTO Players (ID, Name) VALUES (1, 'a')"):expect()
			expect(store.data.Players._schema).toEqual({ "ID", "Name" })
			expect(store.data.Players.rows).toEqual({ { ID = 1, Name = "a" } })
		end)

		it("uses the first column as the key for untyped tables, like 1.x", function()
			local conn = rSQL:connect(FakeDataStore.new(), ALL):expect()
			conn:query("CREATE TABLE Players (ID, Name)"):expect()
			conn:query("INSERT INTO Players (ID, Name) VALUES (1, 'a')"):expect()
			local ok, err = conn:query("INSERT INTO Players (ID, Name) VALUES (1, 'b')"):await()
			expect(ok).toBe(false)
			expect(err).toContain("duplicate key")
		end)

		it("refuses statements the config doesn't allow", function()
			local conn = rSQL:connect(FakeDataStore.new(), { allowCreate = true, allowSelect = true }):expect()
			conn:query("CREATE TABLE T (a)"):expect()
			local ok, err = conn:query("INSERT INTO T (a) VALUES (1)"):await()
			expect(ok).toBe(false)
			expect(err).toContain("INSERT isn't allowed")
		end)

		it("validates connect arguments like 1.x", function()
			local ok, err = rSQL:connect(nil, ALL):await()
			expect(ok).toBe(false)
			expect(err).toContain("datastore")
			ok, err = rSQL:connect(FakeDataStore.new(), nil):await()
			expect(ok).toBe(false)
			expect(err).toContain("config")
		end)

		it("connects to ProfileService and DataKeep profiles", function()
			local profile = { Data = {} }
			local conn = rSQL:connectToProfileService(profile, ALL):expect()
			conn:query("CREATE TABLE Stats (Key, Value)"):expect()
			conn:query("INSERT INTO Stats (Key, Value) VALUES ('wins', 3)"):expect()
			local keep = { Data = profile.Data }
			local again = rSQL:connectToDatakeep(keep, ALL):expect()
			expect(again:query("SELECT Value FROM Stats WHERE Key = 'wins'"):expect()[1].Value).toBe(3)
		end)
	end)

	describe("Promise", function()
		it("chains values and errors", function()
			local log = {}
			Promise.resolve(1)
				:andThen(function(v)
					return v + 1
				end)
				:andThen(function(v)
					error("boom " .. v, 0)
				end)
				:catch(function(e)
					table.insert(log, e)
					return "recovered"
				end)
				:andThen(function(v)
					table.insert(log, v)
				end)
			expect(log).toEqual({ "boom 2", "recovered" })
		end)

		it("adopts returned promises and runs finally", function()
			local status
			local value = Promise.resolve(1)
				:andThen(function()
					return Promise.resolve("inner")
				end)
				:finally(function(s)
					status = s
				end)
				:expect()
			expect(value).toBe("inner")
			expect(status).toBe("Resolved")
		end)

		it("expect raises and await reports rejections", function()
			expect(function()
				Promise.reject("nope"):expect()
			end).toThrow("nope")
			local ok, err = Promise.reject("x"):await()
			expect(ok).toBe(false)
			expect(err).toBe("x")
		end)
	end)
end
