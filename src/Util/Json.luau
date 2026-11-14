--!strict
--[[
	Portable JSON encoder/decoder.

	Roblox has HttpService:JSONEncode and Lune has @lune/serde, but neither exists on
	the other runtime. Keeping our own codec means checkpoints are byte-identical
	everywhere and the core library has no platform dependency.

	Encoding rules:
	  * a table with keys 1..n and nothing else is an array; an empty table is `[]`
	    unless it was created with `Json.object()`
	  * object keys are sorted, so output is deterministic (needed for checksums)
	  * numbers use the shortest of %.14g / %.17g that round-trips exactly
]]

local Json = {}

local OBJECT_MARKER = newproxy(false)
local objectTags = setmetatable({} :: { [any]: boolean }, { __mode = "k" })

function Json.object(t: { [string]: any }?): { [string]: any }
	local obj = t or {}
	objectTags[obj] = true
	return obj
end

Json.null = OBJECT_MARKER

local ESCAPES: { [string]: string } = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\b"] = "\\b",
	["\f"] = "\\f",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

local function escapeString(s: string): string
	return '"'
		.. string.gsub(s, '[%c"\\]', function(c: string): string
			return ESCAPES[c] or string.format("\\u%04x", string.byte(c))
		end)
		.. '"'
end

local function encodeNumber(n: number): string
	if n ~= n or n == math.huge or n == -math.huge then
		error("Json.encode: cannot encode NaN or infinity", 0)
	end
	if n == math.floor(n) and math.abs(n) < 2 ^ 53 then
		return string.format("%d", n)
	end
	local short = string.format("%.14g", n)
	if tonumber(short) == n then
		return short
	end
	return string.format("%.17g", n)
end

local function isArray(t: { [any]: any }, canonical: boolean): (boolean, number)
	if objectTags[t] and not (canonical and next(t) == nil) then
		return false, 0
	end
	local count = 0
	for k in t do
		if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
			return false, 0
		end
		count += 1
	end
	return count == #t, count
end

local function encodeValue(value: any, out: { string }, depth: number, canonical: boolean)
	if depth > 200 then
		error("Json.encode: nesting too deep (cycle?)", 0)
	end
	local kind = type(value)
	if value == nil or value == OBJECT_MARKER then
		table.insert(out, "null")
	elseif kind == "boolean" then
		table.insert(out, if value then "true" else "false")
	elseif kind == "number" then
		table.insert(out, encodeNumber(value))
	elseif kind == "string" then
		table.insert(out, escapeString(value))
	elseif kind == "table" then
		local array, count = isArray(value, canonical)
		if array then
			table.insert(out, "[")
			for i = 1, count do
				if i > 1 then
					table.insert(out, ",")
				end
				encodeValue(value[i], out, depth + 1, canonical)
			end
			table.insert(out, "]")
		else
			local keys: { string } = {}
			for k in value do
				if type(k) ~= "string" then
					error("Json.encode: object keys must be strings, got " .. type(k), 0)
				end
				table.insert(keys, k)
			end
			table.sort(keys)
			table.insert(out, "{")
			for i, k in keys do
				if i > 1 then
					table.insert(out, ",")
				end
				table.insert(out, escapeString(k))
				table.insert(out, ":")
				encodeValue(value[k], out, depth + 1, canonical)
			end
			table.insert(out, "}")
		end
	else
		error("Json.encode: unsupported type " .. kind, 0)
	end
end

--[=[
	With `canonical = true` every empty table encodes as `[]`, so a document
	hashes the same whether it came from Json.decode (tagged objects) or from a
	plain Luau table (e.g. a Rojo JSON module).
]=]
function Json.encode(value: any, canonical: boolean?): string
	local out: { string } = {}
	encodeValue(value, out, 0, canonical == true)
	return table.concat(out)
end

-- Decoder -------------------------------------------------------------------

type Cursor = { s: string, i: number }

local function fail(c: Cursor, msg: string): never
	error(string.format("Json.decode: %s at position %d", msg, c.i), 0)
end

local function skipWhitespace(c: Cursor)
	local _, finish = string.find(c.s, "^[ \t\r\n]*", c.i)
	c.i = (finish :: number) + 1
end

local decodeValue: (c: Cursor) -> any

local function codepointToUtf8(cp: number): string
	return utf8.char(cp)
end

local function decodeString(c: Cursor): string
	c.i += 1 -- opening quote
	local parts: { string } = {}
	local s = c.s
	while true do
		local start = c.i
		local stop = string.find(s, '["\\]', start)
		if not stop then
			fail(c, "unterminated string")
		end
		local stopAt = stop :: number
		if stopAt > start then
			table.insert(parts, string.sub(s, start, stopAt - 1))
		end
		local ch = string.sub(s, stopAt, stopAt)
		if ch == '"' then
			c.i = stopAt + 1
			break
		end
		local esc = string.sub(s, stopAt + 1, stopAt + 1)
		if esc == "u" then
			local hex = string.sub(s, stopAt + 2, stopAt + 5)
			local cp = tonumber(hex, 16)
			if not cp or #hex ~= 4 then
				c.i = stopAt
				fail(c, "invalid unicode escape")
			end
			local code = cp :: number
			local consumed = 6
			if code >= 0xD800 and code <= 0xDBFF and string.sub(s, stopAt + 6, stopAt + 7) == "\\u" then
				local low = tonumber(string.sub(s, stopAt + 8, stopAt + 11), 16)
				if low and low >= 0xDC00 and low <= 0xDFFF then
					code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
					consumed = 12
				end
			end
			table.insert(parts, codepointToUtf8(code))
			c.i = stopAt + consumed
		else
			local map: { [string]: string } = {
				['"'] = '"',
				["\\"] = "\\",
				["/"] = "/",
				b = "\b",
				f = "\f",
				n = "\n",
				r = "\r",
				t = "\t",
			}
			local decoded = map[esc]
			if not decoded then
				c.i = stopAt
				fail(c, "invalid escape '\\" .. esc .. "'")
			end
			table.insert(parts, decoded)
			c.i = stopAt + 2
		end
	end
	return table.concat(parts)
end

local function decodeNumber(c: Cursor): number
	local start, finish = string.find(c.s, "^-?%d+%.?%d*[eE]?[-+]?%d*", c.i)
	if not start then
		fail(c, "invalid number")
	end
	local text = string.sub(c.s, start :: number, finish :: number)
	local n = tonumber(text)
	if n == nil then
		fail(c, "invalid number '" .. text .. "'")
	end
	c.i = (finish :: number) + 1
	return n :: number
end

local function expectLiteral(c: Cursor, literal: string, value: any): any
	if string.sub(c.s, c.i, c.i + #literal - 1) ~= literal then
		fail(c, "unexpected token")
	end
	c.i += #literal
	return value
end

decodeValue = function(c: Cursor): any
	skipWhitespace(c)
	local ch = string.sub(c.s, c.i, c.i)
	if ch == "{" then
		c.i += 1
		local obj = Json.object()
		skipWhitespace(c)
		if string.sub(c.s, c.i, c.i) == "}" then
			c.i += 1
			return obj
		end
		while true do
			skipWhitespace(c)
			if string.sub(c.s, c.i, c.i) ~= '"' then
				fail(c, "expected string key")
			end
			local key = decodeString(c)
			skipWhitespace(c)
			if string.sub(c.s, c.i, c.i) ~= ":" then
				fail(c, "expected ':'")
			end
			c.i += 1
			obj[key] = decodeValue(c)
			skipWhitespace(c)
			local sep = string.sub(c.s, c.i, c.i)
			c.i += 1
			if sep == "}" then
				return obj
			elseif sep ~= "," then
				c.i -= 1
				fail(c, "expected ',' or '}'")
			end
		end
	elseif ch == "[" then
		c.i += 1
		local arr = {}
		skipWhitespace(c)
		if string.sub(c.s, c.i, c.i) == "]" then
			c.i += 1
			return arr
		end
		local n = 0
		while true do
			n += 1
			arr[n] = decodeValue(c)
			skipWhitespace(c)
			local sep = string.sub(c.s, c.i, c.i)
			c.i += 1
			if sep == "]" then
				return arr
			elseif sep ~= "," then
				c.i -= 1
				fail(c, "expected ',' or ']'")
			end
		end
	elseif ch == '"' then
		return decodeString(c)
	elseif ch == "t" then
		return expectLiteral(c, "true", true)
	elseif ch == "f" then
		return expectLiteral(c, "false", false)
	elseif ch == "n" then
		return expectLiteral(c, "null", nil)
	elseif ch == "" then
		fail(c, "unexpected end of input")
	end
	return decodeNumber(c)
end

function Json.decode(text: string): any
	local c: Cursor = { s = text, i = 1 }
	local value = decodeValue(c)
	skipWhitespace(c)
	if c.i <= #text then
		fail(c, "trailing characters")
	end
	return value
end

return Json
