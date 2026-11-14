local Lexer = require("../../src/SQL/Lexer")
local Parser = require("../../src/SQL/Parser")

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	local function kinds(sql)
		local out = {}
		for _, tok in Lexer.tokenize(sql) do
			table.insert(out, tok.kind .. ":" .. tok.value)
		end
		return out
	end

	describe("Lexer", function()
		it("splits keywords, names, numbers, strings and operators", function()
			expect(kinds("select Name, 3.5 from T where x >= 'a'")).toEqual({
				"keyword:SELECT",
				"ident:Name",
				"punct:,",
				"number:3.5",
				"keyword:FROM",
				"ident:T",
				"keyword:WHERE",
				"ident:x",
				"op:>=",
				"string:a",
				"eof:",
			})
		end)

		it("reads escaped quotes, both quote styles and backtick names", function()
			local tokens = Lexer.tokenize("'it''s' \"two\" `select`")
			expect(tokens[1].value).toBe("it's")
			expect(tokens[2].kind).toBe("string")
			expect(tokens[3].kind).toBe("ident")
			expect(tokens[3].value).toBe("select")
		end)

		it("reads numbers in every form", function()
			local tokens = Lexer.tokenize("42 3.25 .5 1e3 2.5E-2")
			expect(tokens[1].number).toBe(42)
			expect(tokens[2].number).toBe(3.25)
			expect(tokens[3].number).toBe(0.5)
			expect(tokens[4].number).toBe(1000)
			expect(tokens[5].number).toBe(0.025)
		end)

		it("skips comments and reads parameters", function()
			expect(kinds("? -- note\n:userId /* block */ <> ")).toEqual({ "param:?", "param:userId", "op:!=", "eof:" })
		end)

		it("points at an unclosed string", function()
			local ok, err = pcall(Lexer.tokenize, "SELECT 'oops")
			expect(ok).toBe(false)
			expect(err).toContain("unclosed string")
			expect(err).toContain("column 8")
		end)
	end)

	describe("Parser", function()
		it("parses a full SELECT", function()
			local s = Parser.parse(
				"SELECT DISTINCT a.Name AS n, COUNT(*) FROM T a LEFT JOIN U ON U.Id = a.Id WHERE x > 1 "
					.. "GROUP BY a.Name HAVING COUNT(*) > 1 ORDER BY n DESC, 2 LIMIT 10 OFFSET 5;"
			)
			expect(s.kind).toBe("select")
			expect(s.distinct).toBe(true)
			expect(#s.items).toBe(2)
			expect(s.items[1].alias).toBe("n")
			expect(s.from.alias).toBe("a")
			expect(s.joins[1].type).toBe("left")
			expect(#s.groupBy).toBe(1)
			expect(s.orderBy[1].desc).toBe(true)
			expect(s.limit.value).toBe(10)
			expect(s.offset.value).toBe(5)
		end)

		it("gives AND a higher precedence than OR", function()
			local s = Parser.parse("SELECT * FROM T WHERE a = 1 OR b = 2 AND c = 3")
			expect(s.where.op).toBe("OR")
			expect(s.where.right.op).toBe("AND")
		end)

		it("parses arithmetic with the usual precedence", function()
			local s = Parser.parse("UPDATE T SET x = x + 2 * 3 - 1")
			local e = s.sets[1].expr
			expect(e.op).toBe("-")
			expect(e.left.op).toBe("+")
			expect(e.left.right.op).toBe("*")
		end)

		it("parses LIKE, IN, BETWEEN and IS NULL, each with NOT", function()
			local s = Parser.parse(
				"SELECT * FROM T WHERE a NOT LIKE 'x%' AND b IN (1, 2) AND c NOT BETWEEN 1 AND 5 AND d IS NOT NULL"
			)
			local parts = {}
			local function walk(e)
				if e.op == "AND" then
					walk(e.left)
					walk(e.right)
				else
					table.insert(parts, e.kind .. ":" .. tostring(e.negate))
				end
			end
			walk(s.where)
			expect(parts).toEqual({ "like:true", "in:false", "between:true", "isnull:true" })
		end)

		it("counts positional parameters and keeps named ones", function()
			local s = Parser.parse("SELECT * FROM T WHERE a = ? AND b = :name AND c = ?")
			expect(s.paramCount).toBe(2)
		end)

		it("parses CREATE TABLE with constraints", function()
			local s = Parser.parse(
				"CREATE TABLE IF NOT EXISTS P (Id INTEGER PRIMARY KEY AUTOINCREMENT, Name VARCHAR(32) NOT NULL UNIQUE, Coins INT DEFAULT 0)"
			)
			expect(s.ifNotExists).toBe(true)
			local defs = s.columnDefs
			expect(defs[1].primaryKey).toBe(true)
			expect(defs[1].autoincrement).toBe(true)
			expect(defs[2].type).toBe("VARCHAR")
			expect(defs[2].notNull).toBe(true)
			expect(defs[2].unique).toBe(true)
			expect(defs[3].default.value).toBe(0)
		end)

		it("parses a table-level PRIMARY KEY", function()
			local s = Parser.parse("CREATE TABLE P (Id INTEGER, Name TEXT, PRIMARY KEY (Id))")
			expect(s.columnDefs[1].primaryKey).toBe(true)
		end)

		it("parses multi-row INSERT, ALTER and the utility statements", function()
			expect(#Parser.parse("INSERT INTO T (a, b) VALUES (1, 2), (3, 4)").rows).toBe(2)
			expect(Parser.parse("ALTER TABLE T ADD COLUMN Age INTEGER").action).toBe("add")
			expect(Parser.parse("ALTER TABLE T DROP Age").action).toBe("drop")
			expect(Parser.parse("ALTER TABLE T RENAME COLUMN a TO b").newName).toBe("b")
			expect(Parser.parse("SHOW TABLES").kind).toBe("showTables")
			expect(Parser.parse("DESCRIBE T").table).toBe("T")
			expect(Parser.parse("EXPLAIN SELECT * FROM T").statement.kind).toBe("select")
			expect(Parser.parse("TRUNCATE TABLE T").kind).toBe("truncate")
			expect(Parser.parse("DROP TABLE IF EXISTS T").ifExists).toBe(true)
		end)

		it("accepts soft keywords as column names", function()
			local s = Parser.parse("SELECT Key, Tables FROM T WHERE Key = 1")
			expect(s.items[1].expr.name).toBe("Key")
		end)

		it("suggests the keyword you probably meant", function()
			expect(function()
				Parser.parse("SELECT Name FORM T")
			end).toThrow("did you mean FROM?")
			expect(function()
				Parser.parse("SELECT Name FROM T WHER Id = 1")
			end).toThrow("did you mean WHERE?")
		end)

		it("reports the position of an error with a caret", function()
			local ok, err = pcall(Parser.parse, "SELECT Name\nFROM T WHERE")
			expect(ok).toBe(false)
			expect(err).toContain("line 2")
			expect(err).toContain("^")
		end)

		it("rejects trailing garbage and non-strings", function()
			expect(function()
				Parser.parse("SELECT * FROM T; DROP TABLE T")
			end).toThrow("after the end of the statement")
			expect(function()
				Parser.parse(42 :: any)
			end).toThrow("query must be a string")
		end)
	end)
end
