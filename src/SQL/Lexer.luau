--!strict
--[[
	Turns a query string into tokens.

	Token kinds:
	  keyword     SELECT, FROM, WHERE ... (case-insensitive, stored upper-case)
	  ident       a name; `backticks` quote names that clash with keywords
	  string      'single' or "double" quotes (both, for 1.x compatibility);
	              a doubled quote inside is an escaped quote: 'it''s'
	  number      42, 3.5, 1e3
	  param       ? (positional) or :name (named)
	  op          = != <> < <= > >= + - * / % ||
	  punct       ( ) , . ;
	  eof

	Comments (-- to end of line, /* block */) are skipped. Every token keeps
	its start position so errors can point at it.
]]

local Errors = require("./Errors")

export type TokenKind = "keyword" | "ident" | "string" | "number" | "param" | "op" | "punct" | "eof"

export type Token = {
	kind: TokenKind,
	value: string,
	number: number?,
	pos: number,
	-- original spelling, for keywords used as names
	text: string?,
}

local Lexer = {}

Lexer.KEYWORDS = {}
for _, word in
	{
		"SELECT",
		"DISTINCT",
		"FROM",
		"WHERE",
		"AND",
		"OR",
		"NOT",
		"IN",
		"IS",
		"NULL",
		"LIKE",
		"BETWEEN",
		"AS",
		"ORDER",
		"BY",
		"ASC",
		"DESC",
		"LIMIT",
		"OFFSET",
		"GROUP",
		"HAVING",
		"JOIN",
		"INNER",
		"LEFT",
		"ON",
		"INSERT",
		"INTO",
		"VALUES",
		"UPDATE",
		"SET",
		"DELETE",
		"CREATE",
		"TABLE",
		"IF",
		"EXISTS",
		"PRIMARY",
		"KEY",
		"UNIQUE",
		"DEFAULT",
		"AUTOINCREMENT",
		"DROP",
		"TRUNCATE",
		"ALTER",
		"ADD",
		"COLUMN",
		"RENAME",
		"TO",
		"TRUE",
		"FALSE",
		"EXPLAIN",
		"SHOW",
		"TABLES",
		"DESCRIBE",
	}
do
	Lexer.KEYWORDS[word] = true
end

local TWO_CHAR_OPS = { ["!="] = true, ["<>"] = true, ["<="] = true, [">="] = true, ["||"] = true, ["=="] = true }
local ONE_CHAR_OPS =
	{ ["="] = true, ["<"] = true, [">"] = true, ["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true, ["%"] = true }
local PUNCT = { ["("] = true, [")"] = true, [","] = true, ["."] = true, [";"] = true }

function Lexer.tokenize(query: string): { Token }
	local tokens: { Token } = {}
	local n = #query
	local i = 1

	local function push(kind: TokenKind, value: string, pos: number, number: number?, text: string?)
		table.insert(tokens, { kind = kind, value = value, pos = pos, number = number, text = text })
	end

	while i <= n do
		local c = string.sub(query, i, i)
		local start = i

		if string.match(c, "%s") then
			i += 1
		elseif c == "-" and string.sub(query, i + 1, i + 1) == "-" then
			local stop = string.find(query, "\n", i, true)
			i = if stop then stop + 1 else n + 1
		elseif c == "/" and string.sub(query, i + 1, i + 1) == "*" then
			local stop = string.find(query, "*/", i + 2, true)
			if not stop then
				Errors.raise("syntax", "unclosed /* comment", start, query)
			end
			i = (stop :: number) + 2
		elseif c == "'" or c == '"' then
			local parts = {}
			i += 1
			while true do
				if i > n then
					Errors.raise("syntax", "unclosed string", start, query)
				end
				local ch = string.sub(query, i, i)
				if ch == c then
					if string.sub(query, i + 1, i + 1) == c then
						table.insert(parts, c)
						i += 2
					else
						i += 1
						break
					end
				else
					table.insert(parts, ch)
					i += 1
				end
			end
			push("string", table.concat(parts), start)
		elseif c == "`" then
			local stop = string.find(query, "`", i + 1, true)
			if not stop then
				Errors.raise("syntax", "unclosed `quoted name`", start, query)
			end
			push("ident", string.sub(query, i + 1, (stop :: number) - 1), start)
			i = (stop :: number) + 1
		elseif string.match(c, "%d") or (c == "." and string.match(string.sub(query, i + 1, i + 1), "%d")) then
			local text = string.match(query, "^%d*%.?%d+[eE][%+%-]?%d+", i)
				or string.match(query, "^%d+%.%d*", i)
				or string.match(query, "^%d*%.%d+", i)
				or string.match(query, "^%d+", i)
			local value = text :: string
			i += #value
			if string.match(string.sub(query, i, i), "[%a_]") then
				Errors.raise("syntax", "invalid number '" .. value .. string.sub(query, i, i) .. "'", start, query)
			end
			push("number", value, start, tonumber(value))
		elseif string.match(c, "[%a_]") then
			local word = string.match(query, "^[%w_]+", i) :: string
			i += #word
			local upper = string.upper(word)
			if Lexer.KEYWORDS[upper] then
				push("keyword", upper, start, nil, word)
			else
				push("ident", word, start)
			end
		elseif c == "?" then
			push("param", "?", start)
			i += 1
		elseif c == ":" and string.match(string.sub(query, i + 1, i + 1), "[%a_]") then
			local name = string.match(query, "^[%w_]+", i + 1) :: string
			push("param", name, start)
			i += 1 + #name
		else
			local two = string.sub(query, i, i + 1)
			if TWO_CHAR_OPS[two] then
				push("op", if two == "<>" then "!=" elseif two == "==" then "=" else two, start)
				i += 2
			elseif ONE_CHAR_OPS[c] then
				push("op", c, start)
				i += 1
			elseif PUNCT[c] then
				push("punct", c, start)
				i += 1
			else
				Errors.raise("syntax", "unexpected character '" .. c .. "'", start, query)
			end
		end
	end
	push("eof", "", n + 1)
	return tokens
end

return Lexer
