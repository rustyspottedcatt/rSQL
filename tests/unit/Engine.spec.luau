local rSQL = require("../../src")
local Types = require("../../src/Engine/Types")

return function(t)
	local describe, it, expect, beforeEach = t.describe, t.it, t.expect, t.beforeEach

	local function names(result, column)
		local out = {}
		for _, row in result.rows do
			table.insert(out, row[column or "Name"])
		end
		return out
	end

	local db
	beforeEach(function()
		db = rSQL.memory()
		db:exec(
			"CREATE TABLE Players (UserId INTEGER PRIMARY KEY, Name TEXT NOT NULL, Coins INTEGER DEFAULT 0, Team TEXT, Level INTEGER)"
		)
		db:exec([[INSERT INTO Players (UserId, Name, Coins, Team, Level) VALUES
			(1, 'alice', 120, 'red', 5),
			(2, 'bob', 40, 'blue', 2),
			(3, 'carol', 75, 'red', NULL),
			(4, 'dave', 40, 'green', 8),
			(5, 'Erin', 0, 'blue', 3)]])
	end)

	describe("Types", function()
		it("coerces values into column types", function()
			expect(Types.coerce("500", "INTEGER")).toBe(500)
			expect(select(2, Types.coerce("5.5", "INTEGER"))).toContain("whole number")
			expect(Types.coerce(3, "TEXT")).toBe("3")
			expect(Types.coerce("true", "BOOLEAN")).toBe(true)
			expect(select(2, Types.coerce("abc", "REAL"))).toContain("expected a number")
			expect(Types.coerce(buffer.create(2), "BLOB") ~= nil).toBe(true)
		end)

		it("compares numbers with numeric strings and refuses NULL", function()
			expect(Types.compare(10, "9")).toBe(1)
			expect(Types.compare("abc", "abd")).toBe(-1)
			expect(Types.compare(nil, 1)).toBeNil()
		end)
	end)

	describe("SELECT", function()
		it("filters with comparisons and boolean logic", function()
			local r =
				db:exec("SELECT Name FROM Players WHERE Coins >= 40 AND (Team = 'red' OR Level > 7) ORDER BY UserId")
			expect(names(r)).toEqual({ "alice", "carol", "dave" })
		end)

		it("treats NULL like SQL does", function()
			expect(#db:exec("SELECT * FROM Players WHERE Level > 0").rows).toBe(4)
			expect(names(db:exec("SELECT Name FROM Players WHERE Level IS NULL"))).toEqual({ "carol" })
			expect(#db:exec("SELECT * FROM Players WHERE NOT (Level > 0)").rows).toBe(0)
		end)

		it("matches LIKE patterns case-insensitively", function()
			expect(names(db:exec("SELECT Name FROM Players WHERE Name LIKE 'e%' ORDER BY Name"))).toEqual({ "Erin" })
			expect(names(db:exec("SELECT Name FROM Players WHERE Name LIKE '_o%'"))).toEqual({ "bob" })
			expect(#db:exec("SELECT * FROM Players WHERE Name NOT LIKE '%a%'").rows).toBe(2)
		end)

		it("supports IN and BETWEEN", function()
			expect(names(db:exec("SELECT Name FROM Players WHERE UserId IN (2, 4) ORDER BY UserId"))).toEqual({
				"bob",
				"dave",
			})
			expect(names(db:exec("SELECT Name FROM Players WHERE Coins BETWEEN 40 AND 75 ORDER BY Name"))).toEqual({
				"bob",
				"carol",
				"dave",
			})
		end)

		it("orders by several keys, by alias and by position", function()
			local r = db:exec("SELECT Name, Coins AS c FROM Players ORDER BY c DESC, Name ASC")
			expect(names(r)).toEqual({ "alice", "carol", "bob", "dave", "Erin" })
			expect(names(db:exec("SELECT Name, Coins FROM Players ORDER BY 2, 1 LIMIT 2"))).toEqual({ "Erin", "bob" })
		end)

		it("puts NULLs first when sorting ascending", function()
			expect(names(db:exec("SELECT Name FROM Players ORDER BY Level"))[1]).toBe("carol")
		end)

		it("applies LIMIT and OFFSET", function()
			expect(names(db:exec("SELECT Name FROM Players ORDER BY UserId LIMIT 2 OFFSET 1"))).toEqual({
				"bob",
				"carol",
			})
			expect(names(db:exec("SELECT Name FROM Players ORDER BY UserId LIMIT 3, 1"))).toEqual({ "dave" })
		end)

		it("removes duplicates with DISTINCT", function()
			expect(names(db:exec("SELECT DISTINCT Team FROM Players ORDER BY Team"), "Team")).toEqual({
				"blue",
				"green",
				"red",
			})
		end)

		it("groups and aggregates", function()
			local r = db:exec(
				"SELECT Team, COUNT(*) AS n, SUM(Coins) AS total, AVG(Coins) AS avg, MIN(Name) AS first, MAX(Level) AS top "
					.. "FROM Players GROUP BY Team HAVING COUNT(*) > 1 ORDER BY total DESC"
			)
			expect(#r.rows).toBe(2)
			expect(r.rows[1]).toEqual({ Team = "red", n = 2, total = 195, avg = 97.5, first = "alice", top = 5 })
			expect(r.rows[2]).toEqual({ Team = "blue", n = 2, total = 40, avg = 20, first = "Erin", top = 3 })
		end)

		it("aggregates over the whole table, including an empty one", function()
			local r =
				db:exec("SELECT COUNT(*) AS n, COUNT(Level) AS withLevel, COUNT(DISTINCT Team) AS teams FROM Players")
			expect(r.rows[1]).toEqual({ n = 5, withLevel = 4, teams = 3 })
			local empty = db:exec("SELECT COUNT(*) AS n, SUM(Coins) AS s FROM Players WHERE Coins > 1000")
			expect(empty.rows[1].n).toBe(0)
			expect(empty.rows[1].s).toBeNil()
		end)

		it("evaluates arithmetic and functions", function()
			local r = db:exec(
				"SELECT UPPER(Name) AS n, Coins * 2 + 1 AS c, LENGTH(Name) AS len FROM Players WHERE UserId = 2"
			)
			expect(r.rows[1]).toEqual({ n = "BOB", c = 81, len = 3 })
			expect(db:exec("SELECT COALESCE(Level, -1) AS l FROM Players WHERE UserId = 3").rows[1].l).toBe(-1)
			expect(db:exec("SELECT ROUND(Coins / 7, 2) AS r FROM Players WHERE UserId = 1").rows[1].r).toBe(17.14)
		end)

		it("joins tables with INNER and LEFT JOIN", function()
			db:exec("CREATE TABLE Items (Id INTEGER PRIMARY KEY AUTOINCREMENT, Owner INTEGER, Item TEXT)")
			db:exec("INSERT INTO Items (Owner, Item) VALUES (1, 'sword'), (1, 'shield'), (3, 'bow')")
			local inner =
				db:exec("SELECT p.Name, i.Item FROM Players p JOIN Items i ON i.Owner = p.UserId ORDER BY i.Id")
			expect(#inner.rows).toBe(3)
			expect(inner.rows[3]).toEqual({ Name = "carol", Item = "bow" })
			local left = db:exec(
				"SELECT p.Name, COUNT(i.Id) AS items FROM Players p LEFT JOIN Items i ON p.UserId = i.Owner "
					.. "GROUP BY p.Name ORDER BY items DESC, p.Name"
			)
			expect(left.rows[1]).toEqual({ Name = "alice", items = 2 })
			expect(#left.rows).toBe(5)
		end)

		it("joins on a non-equality condition", function()
			db:exec("CREATE TABLE Ranks (Rank TEXT PRIMARY KEY, MinCoins INTEGER)")
			db:exec("INSERT INTO Ranks VALUES ('bronze', 0), ('silver', 50), ('gold', 100)")
			local r = db:exec(
				"SELECT p.Name, r.Rank FROM Players p JOIN Ranks r ON p.Coins >= r.MinCoins WHERE p.UserId = 1 ORDER BY r.MinCoins"
			)
			expect(names(r, "Rank")).toEqual({ "bronze", "silver", "gold" })
		end)

		it("expands * and keeps the hidden row id out of it", function()
			db:exec("CREATE TABLE Log (Message TEXT)")
			db:exec("INSERT INTO Log VALUES ('hi')")
			expect(db:exec("SELECT * FROM Log").columns).toEqual({ "Message" })
		end)

		it("binds positional, named and NULL parameters", function()
			expect(names(db:exec("SELECT Name FROM Players WHERE Team = ? AND Coins > ?", { "red", 100 }))).toEqual({
				"alice",
			})
			expect(names(db:exec("SELECT Name FROM Players WHERE UserId = :id", { id = 4 }))).toEqual({ "dave" })
			db:exec("UPDATE Players SET Team = ? WHERE UserId = 4", { rSQL.NULL })
			expect(db:exec("SELECT Team FROM Players WHERE UserId = 4").rows[1].Team).toBeNil()
		end)

		it("treats parameter values as data, never as SQL", function()
			local evil = "x' OR '1'='1"
			expect(#db:exec("SELECT * FROM Players WHERE Name = ?", { evil }).rows).toBe(0)
		end)

		it("reports missing parameters", function()
			expect(function()
				db:exec("SELECT * FROM Players WHERE UserId = ?")
			end).toThrow("missing value for parameter ?1")
			expect(function()
				db:exec("SELECT * FROM Players WHERE UserId = :id", {})
			end).toThrow("missing value for parameter :id")
		end)

		it("uses a key lookup when WHERE pins the primary key", function()
			local r = db:exec("SELECT Name FROM Players WHERE UserId = ? AND Coins > 0", { 2 })
			expect(r.plan[1]).toBe("key lookup on UserId")
			expect(db:exec("SELECT * FROM Players WHERE UserId IN (1, 3)").plan[1]).toContain("2 keys")
			expect(db:exec("SELECT * FROM Players WHERE Coins = 40").plan[1]).toContain("full scan")
		end)

		it("explains its plan", function()
			local plan = db:explain("SELECT * FROM Players WHERE UserId = 1 ORDER BY Name LIMIT 1")
			expect(plan).toEqual({ "key lookup on UserId", "filter WHERE", "sort", "limit" })
		end)

		it("names unknown columns and suggests close ones", function()
			expect(function()
				db:exec("SELECT Nmae FROM Players")
			end).toThrow("did you mean Name?")
		end)

		it("points at unknown tables and suggests close ones", function()
			expect(function()
				db:exec("UPDATE Playrs SET Coins = 1")
			end).toThrow("no table named Playrs (did you mean Players?) (line 1, column 8)")
		end)

		it("rejects ambiguous columns in joins", function()
			db:exec("CREATE TABLE Other (UserId INTEGER PRIMARY KEY)")
			expect(function()
				db:exec("SELECT UserId FROM Players JOIN Other ON Players.UserId = Other.UserId")
			end).toThrow("ambiguous")
		end)
	end)

	describe("Writes", function()
		it("converts values to the column type", function()
			db:exec("INSERT INTO Players (UserId, Name, Coins) VALUES ('6', 'fay', '250')")
			local row = db:exec("SELECT UserId, Coins FROM Players WHERE UserId = 6").rows[1]
			expect(typeof(row.UserId)).toBe("number")
			expect(row.Coins).toBe(250)
		end)

		it("applies defaults and enforces NOT NULL and types", function()
			db:exec("INSERT INTO Players (UserId, Name) VALUES (7, 'gus')")
			expect(db:exec("SELECT Coins FROM Players WHERE UserId = 7").rows[1].Coins).toBe(0)
			expect(function()
				db:exec("INSERT INTO Players (UserId) VALUES (8)")
			end).toThrow("can't be NULL")
			expect(function()
				db:exec("INSERT INTO Players (UserId, Name, Coins) VALUES (9, 'x', 'lots')")
			end).toThrow("expected a number")
		end)

		it("rejects duplicate keys and unknown columns", function()
			expect(function()
				db:exec("INSERT INTO Players (UserId, Name) VALUES (1, 'again')")
			end).toThrow("duplicate key '1'")
			expect(function()
				db:exec("INSERT INTO Players (UserId, Nick) VALUES (10, 'x')")
			end).toThrow("no column Nick")
		end)

		it("hands out AUTOINCREMENT ids", function()
			db:exec("CREATE TABLE Items (Id INTEGER PRIMARY KEY AUTOINCREMENT, Item TEXT)")
			local r = db:exec("INSERT INTO Items (Item) VALUES ('a'), ('b')")
			expect(r.insertIds).toEqual({ 1, 2 })
			expect(db:exec("INSERT INTO Items (Item) VALUES ('c')").lastInsertId).toBe(3)
		end)

		it("enforces UNIQUE", function()
			db:exec("CREATE TABLE Names (Id INTEGER PRIMARY KEY, Name TEXT UNIQUE)")
			db:exec("INSERT INTO Names VALUES (1, 'a'), (2, 'b')")
			expect(function()
				db:exec("INSERT INTO Names VALUES (3, 'a')")
			end).toThrow("must be unique")
			expect(function()
				db:exec("UPDATE Names SET Name = 'b' WHERE Id = 1")
			end).toThrow("must be unique")
		end)

		it("updates with expressions and reports how many rows changed", function()
			local r =
				db:exec("UPDATE Players SET Coins = Coins + 10, Level = COALESCE(Level, 0) + 1 WHERE Team = 'blue'")
			expect(r.affected).toBe(2)
			local rows = db:exec("SELECT Coins, Level FROM Players WHERE Team = 'blue' ORDER BY UserId").rows
			expect(rows).toEqual({ { Coins = 50, Level = 3 }, { Coins = 10, Level = 4 } })
		end)

		it("deletes matching rows", function()
			expect(db:exec("DELETE FROM Players WHERE Coins < 50").affected).toBe(3)
			expect(#db:exec("SELECT * FROM Players").rows).toBe(2)
		end)

		it("CREATE TABLE refuses to replace a table", function()
			expect(function()
				db:exec("CREATE TABLE Players (Id INTEGER)")
			end).toThrow("already exists")
			db:exec("CREATE TABLE IF NOT EXISTS Players (Id INTEGER)")
			expect(#db:exec("SELECT * FROM Players").rows).toBe(5)
		end)

		it("alters tables", function()
			db:exec("ALTER TABLE Players ADD COLUMN Gems INTEGER NOT NULL DEFAULT 5")
			expect(db:exec("SELECT Gems FROM Players WHERE UserId = 1").rows[1].Gems).toBe(5)
			db:exec("ALTER TABLE Players RENAME COLUMN Gems TO Crystals")
			expect(db:exec("SELECT Crystals FROM Players WHERE UserId = 1").rows[1].Crystals).toBe(5)
			db:exec("ALTER TABLE Players DROP COLUMN Crystals")
			expect(function()
				db:exec("SELECT Crystals FROM Players")
			end).toThrow("no column Crystals")
			expect(function()
				db:exec("ALTER TABLE Players DROP COLUMN UserId")
			end).toThrow("primary key")
		end)

		it("describes, lists, truncates and drops tables", function()
			local d = db:exec("DESCRIBE Players")
			expect(d.rows[1]).toEqual({ column = "UserId", type = "INTEGER", key = "PRIMARY", nullable = false })
			expect(names(db:exec("SHOW TABLES"), "name")).toEqual({ "Players" })
			db:exec("TRUNCATE TABLE Players")
			expect(#db:exec("SELECT * FROM Players").rows).toBe(0)
			db:exec("DROP TABLE Players")
			expect(#db:exec("SHOW TABLES").rows).toBe(0)
			db:exec("DROP TABLE IF EXISTS Players")
		end)
	end)

	describe("Database handle", function()
		it("enforces permissions", function()
			local readOnly = rSQL.open(db.adapter, { permissions = "read" })
			expect(#readOnly:exec("SELECT * FROM Players").rows).toBe(5)
			expect(function()
				readOnly:exec("DELETE FROM Players")
			end).toThrow("DELETE isn't allowed")
			expect(function()
				readOnly:exec("EXPLAIN DELETE FROM Players")
			end).toThrow("isn't allowed")
		end)

		it("caches parsed statements and runs prepared ones", function()
			local stmt = db:prepare("SELECT Name FROM Players WHERE UserId = ?")
			expect(stmt:run({ 1 }).rows[1].Name).toBe("alice")
			expect(stmt:run({ 2 }).rows[1].Name).toBe("bob")
			db:exec("SELECT 1 FROM Players")
			db:exec("SELECT 1 FROM Players")
			expect(db.stats.cacheHits).toBeGreaterThan(0)
		end)

		it("reports every query to onQuery", function()
			local seen = {}
			local watched = rSQL.open(db.adapter, {
				onQuery = function(info)
					table.insert(seen, info)
				end,
			})
			watched:exec("SELECT * FROM Players")
			pcall(watched.exec, watched, "SELECT nope FROM Players")
			expect(#seen).toBe(2)
			expect(seen[1].ok).toBe(true)
			expect(seen[1].rows).toBe(5)
			expect(seen[2].ok).toBe(false)
		end)

		it("returns a promise from query", function()
			local rows = db:query("SELECT Name FROM Players WHERE UserId = 1"):expect().rows
			expect(rows[1].Name).toBe("alice")
			local ok, err = db:query("SELECT broken FROM"):await()
			expect(ok).toBe(false)
			expect(err).toContain("rSQL")
		end)
	end)
end
