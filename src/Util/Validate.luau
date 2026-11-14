--!strict
--[[
	Declarative config validation.

	Every public constructor validates its options against a schema and reports
	all problems at once, e.g.

	  GPTConfig is invalid:
	    - dModel: expected integer >= 1, got 0
	    - numHeads: must divide dModel (64 % 6 ~= 0)
]]

export type FieldSpec = {
	type: "number" | "integer" | "string" | "boolean" | "table" | "function",
	optional: boolean?,
	min: number?,
	max: number?,
	oneOf: { string }?,
	default: any?,
}

export type Schema = { [string]: FieldSpec }
export type Rule = (config: { [string]: any }) -> string?

local Validate = {}

local function describe(spec: FieldSpec): string
	local parts = { spec.type }
	if spec.min and spec.max then
		table.insert(parts, string.format("in [%s, %s]", tostring(spec.min), tostring(spec.max)))
	elseif spec.min then
		table.insert(parts, ">= " .. tostring(spec.min))
	elseif spec.max then
		table.insert(parts, "<= " .. tostring(spec.max))
	end
	if spec.oneOf then
		table.insert(parts, "one of {" .. table.concat(spec.oneOf, ", ") .. "}")
	end
	return table.concat(parts, " ")
end

local function checkField(name: string, value: any, spec: FieldSpec): string?
	if value == nil then
		if spec.optional or spec.default ~= nil then
			return nil
		end
		return string.format("%s: required %s is missing", name, describe(spec))
	end
	local ok: boolean
	if spec.type == "integer" then
		ok = type(value) == "number" and value % 1 == 0
	else
		ok = type(value) == spec.type
	end
	if ok and type(value) == "number" then
		local outOfRange = (spec.min ~= nil and value < spec.min) or (spec.max ~= nil and value > spec.max)
		ok = value == value and not outOfRange
	end
	if ok and spec.oneOf then
		ok = table.find(spec.oneOf, value) ~= nil
	end
	if not ok then
		return string.format("%s: expected %s, got %s", name, describe(spec), tostring(value))
	end
	return nil
end

--[=[
	Returns a new table with defaults filled in. Throws one error listing every
	problem. Unknown keys are rejected so typos (`numHead`) fail loudly.
]=]
function Validate.check(label: string, config: { [string]: any }?, schema: Schema, rules: { Rule }?): { [string]: any }
	if config ~= nil and type(config) ~= "table" then
		error(string.format("%s must be a table, got %s", label, type(config)), 3)
	end
	local input: { [string]: any } = config or {}
	local problems: { string } = {}

	for key in input do
		if type(key) ~= "string" or schema[key] == nil then
			table.insert(problems, string.format("%s: unknown option", tostring(key)))
		end
	end

	local result: { [string]: any } = {}
	local names: { string } = {}
	for name in schema do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local spec = schema[name]
		local value = input[name]
		local problem = checkField(name, value, spec)
		if problem then
			table.insert(problems, problem)
		end
		if value == nil then
			value = spec.default
		end
		result[name] = value
	end

	if #problems == 0 and rules then
		for _, rule in rules do
			local problem = rule(result)
			if problem then
				table.insert(problems, problem)
			end
		end
	end

	if #problems > 0 then
		table.sort(problems)
		error(string.format("%s is invalid:\n  - %s", label, table.concat(problems, "\n  - ")), 3)
	end
	return result
end

return Validate
