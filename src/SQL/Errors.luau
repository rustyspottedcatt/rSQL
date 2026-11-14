--!strict
--[[
	Errors with a position in the query.

	Parse errors point at the character that went wrong:

	    rSQL: expected FROM, got 'WHER' (line 1, column 13)
	      SELECT Name WHER UserId = 1
	                  ^
]]

export type SqlError = {
	kind: "syntax" | "semantic" | "permission" | "constraint" | "storage",
	message: string,
	position: number?,
	query: string?,
}

local Errors = {}

local function lineAndColumn(query: string, position: number): (number, number, string)
	local line, lineStart = 1, 1
	for i = 1, math.min(position - 1, #query) do
		if string.byte(query, i) == 10 then
			line += 1
			lineStart = i + 1
		end
	end
	local lineEnd = string.find(query, "\n", lineStart, true)
	local text = string.sub(query, lineStart, if lineEnd then lineEnd - 1 else #query)
	return line, position - lineStart + 1, text
end

function Errors.format(err: SqlError): string
	local position, query = err.position, err.query
	if position and query then
		local line, column, text = lineAndColumn(query, position)
		return string.format(
			"rSQL: %s (line %d, column %d)\n  %s\n  %s^",
			err.message,
			line,
			column,
			text,
			string.rep(" ", column - 1)
		)
	end
	return "rSQL: " .. err.message
end

-- Raises a formatted error. `level` 0 keeps Luau from prefixing a script path.
function Errors.raise(kind: string, message: string, position: number?, query: string?): never
	error(Errors.format({ kind = kind :: any, message = message, position = position, query = query }), 0)
end

return Errors
