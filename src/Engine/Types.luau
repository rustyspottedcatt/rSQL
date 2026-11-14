--!strict
--[[
	Column types and value rules.

	    INTEGER   whole numbers          (INT, BIGINT)
	    REAL      any number             (FLOAT, DOUBLE, NUMBER, NUMERIC, DECIMAL)
	    TEXT      strings                (STRING, VARCHAR, CHAR)
	    BOOLEAN   true / false           (BOOL)
	    JSON      any table DataStores can save
	    BLOB      buffers or raw strings (BUFFER)
	    ANY       no checks (untyped columns, and every column of a 1.x table)

	Values are converted when they are written, so a column declared INTEGER
	always reads back as a number even if the query wrote '500'. That is the
	fix for 1.x returning every number as a string.

	SQL NULL is Luau nil.
]]

local Types = {}

local ALIASES: { [string]: string } = {
	INTEGER = "INTEGER",
	INT = "INTEGER",
	BIGINT = "INTEGER",
	SMALLINT = "INTEGER",
	REAL = "REAL",
	FLOAT = "REAL",
	DOUBLE = "REAL",
	NUMBER = "REAL",
	NUMERIC = "REAL",
	DECIMAL = "REAL",
	TEXT = "TEXT",
	STRING = "TEXT",
	VARCHAR = "TEXT",
	CHAR = "TEXT",
	BOOLEAN = "BOOLEAN",
	BOOL = "BOOLEAN",
	JSON = "JSON",
	BLOB = "BLOB",
	BUFFER = "BLOB",
	ANY = "ANY",
}

function Types.normalize(name: string): string?
	return ALIASES[string.upper(name)]
end

function Types.names(): string
	return "INTEGER, REAL, TEXT, BOOLEAN, JSON, BLOB, ANY"
end

--[=[
	Converts `value` for a column of type `columnType`. Returns the converted
	value, or nil plus a reason when it can't be stored in that column.
]=]
function Types.coerce(value: any, columnType: string): (any, string?)
	if value == nil then
		return nil, nil
	end
	local kind = typeof(value)
	if columnType == "ANY" then
		return value, nil
	elseif columnType == "INTEGER" or columnType == "REAL" then
		local n: number? = nil
		if kind == "number" then
			n = value
		elseif kind == "string" then
			n = tonumber(value)
		elseif kind == "boolean" then
			n = if value then 1 else 0
		end
		if n == nil or n ~= n then
			return nil, "expected a number, got " .. (if kind == "string" then "'" .. value .. "'" else kind)
		end
		if columnType == "INTEGER" and (n :: number) % 1 ~= 0 then
			return nil, "expected a whole number, got " .. tostring(n)
		end
		return n, nil
	elseif columnType == "TEXT" then
		if kind == "string" then
			return value, nil
		elseif kind == "number" or kind == "boolean" then
			return tostring(value), nil
		end
		return nil, "expected text, got " .. kind
	elseif columnType == "BOOLEAN" then
		if kind == "boolean" then
			return value, nil
		elseif value == 1 or value == "1" or value == "true" or value == "TRUE" then
			return true, nil
		elseif value == 0 or value == "0" or value == "false" or value == "FALSE" then
			return false, nil
		end
		return nil, "expected a boolean, got " .. tostring(value)
	elseif columnType == "JSON" then
		if kind == "function" or kind == "thread" or kind == "userdata" then
			return nil, "can't store a " .. kind
		end
		return value, nil
	elseif columnType == "BLOB" then
		if kind == "buffer" or kind == "string" then
			return value, nil
		end
		return nil, "expected a buffer or string, got " .. kind
	end
	return nil, "unknown column type " .. columnType
end

--[=[
	SQL-style comparison. Returns -1, 0, 1, or nil when the values can't be
	ordered (NULL, or mixed types). A number and a numeric string compare as
	numbers so rows written as text by 1.x still filter correctly.
]=]
function Types.compare(a: any, b: any): number?
	if a == nil or b == nil then
		return nil
	end
	local ta, tb = typeof(a), typeof(b)
	if ta ~= tb then
		if ta == "number" and tb == "string" then
			local nb = tonumber(b)
			if nb == nil then
				return nil
			end
			b, tb = nb, "number"
		elseif ta == "string" and tb == "number" then
			local na = tonumber(a)
			if na == nil then
				return nil
			end
			a, ta = na, "number"
		else
			return nil
		end
	end
	if ta == "number" or ta == "string" then
		if a < b then
			return -1
		elseif a > b then
			return 1
		end
		return 0
	elseif ta == "boolean" then
		if a == b then
			return 0
		end
		return if a then 1 else -1
	end
	return if a == b then 0 else nil
end

-- Sort order for ORDER BY: NULLs first, then numbers, strings, booleans.
local RANK = { ["nil"] = 0, number = 1, string = 2, boolean = 3 }
function Types.sortCompare(a: any, b: any): number
	local c = Types.compare(a, b)
	if c then
		return c
	end
	local ra = RANK[typeof(a)] or 4
	local rb = RANK[typeof(b)] or 4
	if ra ~= rb then
		return if ra < rb then -1 else 1
	end
	return 0
end

-- Truthiness of a WHERE result: only `true` passes (NULL and false don't).
function Types.truthy(v: any): boolean
	if v == true then
		return true
	elseif typeof(v) == "number" then
		return v ~= 0
	end
	return false
end

-- Key under which a primary-key value is stored.
function Types.key(value: any): string
	return tostring(value)
end

return Types
