--!strict
--[[
	Small BDD-style test framework (describe / it / expect) with no
	dependencies, so the suite runs anywhere Luau runs.
]]

export type Expectation = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeCloseTo: (expected: number, tolerance: number?) -> (),
	toBeGreaterThan: (n: number) -> (),
	toBeLessThan: (n: number) -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
	toBeNil: () -> (),
	toContain: (needle: any) -> (),
	toThrow: (pattern: string?) -> (),
	never: Expectation,
}

export type TestCase = { name: string, fn: () -> () }
export type Suite = { name: string, tests: { TestCase }, before: { () -> () } }

local TestKit = {}

local suites: { Suite } = {}
local currentPath: { string } = {}
local currentBefore: { { () -> () } } = { {} } -- root scope for hooks outside any describe

local function inspect(v: any, depth: number?): string
	local d = depth or 0
	if type(v) == "string" then
		return string.format("%q", v)
	elseif type(v) ~= "table" then
		return tostring(v)
	elseif d > 2 then
		return "{...}"
	end
	local parts = {}
	local count = 0
	for k, val in v do
		count += 1
		if count > 8 then
			table.insert(parts, "...")
			break
		end
		table.insert(parts, string.format("[%s]=%s", inspect(k, d + 1), inspect(val, d + 1)))
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function makeExpect(actual: any, negate: boolean): Expectation
	local e = {} :: any

	local function check(ok: boolean, message: string)
		if negate then
			ok = not ok
			message = "NOT " .. message
		end
		if not ok then
			error(message, 3)
		end
	end

	e.toBe = function(expected: any)
		check(actual == expected, string.format("expected %s to be %s", inspect(actual), inspect(expected)))
	end
	e.toEqual = function(expected: any)
		check(deepEqual(actual, expected), string.format("expected %s to equal %s", inspect(actual), inspect(expected)))
	end
	e.toBeCloseTo = function(expected: number, tolerance: number?)
		local tol = tolerance or 1e-9
		check(
			type(actual) == "number" and math.abs(actual - expected) <= tol,
			string.format("expected %s to be within %g of %s", tostring(actual), tol, tostring(expected))
		)
	end
	e.toBeGreaterThan = function(n: number)
		check(actual > n, string.format("expected %s > %s", tostring(actual), tostring(n)))
	end
	e.toBeLessThan = function(n: number)
		check(actual < n, string.format("expected %s < %s", tostring(actual), tostring(n)))
	end
	e.toBeTruthy = function()
		check(not not actual, string.format("expected %s to be truthy", inspect(actual)))
	end
	e.toBeFalsy = function()
		check(not actual, string.format("expected %s to be falsy", inspect(actual)))
	end
	e.toBeNil = function()
		check(actual == nil, string.format("expected %s to be nil", inspect(actual)))
	end
	e.toContain = function(needle: any)
		local found = false
		if type(actual) == "string" then
			found = string.find(actual, needle, 1, true) ~= nil
		elseif type(actual) == "table" then
			found = table.find(actual, needle) ~= nil
		end
		check(found, string.format("expected %s to contain %s", inspect(actual), inspect(needle)))
	end
	e.toThrow = function(pattern: string?)
		local ok, err = pcall(actual)
		local matched = not ok and (pattern == nil or string.find(tostring(err), pattern, 1, true) ~= nil)
		check(
			matched,
			if ok
				then "expected function to throw"
				else string.format("expected error matching %q, got %q", pattern or "", tostring(err))
		)
	end
	if not negate then
		e.never = makeExpect(actual, true)
	end
	return e :: Expectation
end

function TestKit.expect(actual: any): Expectation
	return makeExpect(actual, false)
end

function TestKit.describe(name: string, fn: () -> ())
	table.insert(currentPath, name)
	table.insert(currentBefore, {})
	fn()
	table.remove(currentBefore)
	table.remove(currentPath)
end

function TestKit.beforeEach(fn: () -> ())
	table.insert(currentBefore[#currentBefore], fn)
end

function TestKit.it(name: string, fn: () -> ())
	local suiteName = table.concat(currentPath, " > ")
	local suite = suites[#suites]
	if not suite or suite.name ~= suiteName then
		local before = {}
		for _, list in currentBefore do
			for _, hook in list do
				table.insert(before, hook)
			end
		end
		suite = { name = suiteName, tests = {}, before = before }
		table.insert(suites, suite)
	end
	table.insert(suite.tests, { name = name, fn = fn })
end

export type Report = { passed: number, failed: number, failures: { { name: string, err: string } } }

function TestKit.run(filter: string?, clock: () -> number): Report
	local report: Report = { passed = 0, failed = 0, failures = {} }
	for _, suite in suites do
		local header = false
		for _, test in suite.tests do
			local full = suite.name .. " > " .. test.name
			if filter == nil or string.find(string.lower(full), string.lower(filter), 1, true) then
				if not header then
					print("\n" .. suite.name)
					header = true
				end
				local t0 = clock()
				local ok, err = pcall(function()
					for _, hook in suite.before do
						hook()
					end
					test.fn()
				end)
				local ms = (clock() - t0) * 1000
				if ok then
					report.passed += 1
					print(string.format("  [PASS] %s (%.0f ms)", test.name, ms))
				else
					report.failed += 1
					table.insert(report.failures, { name = full, err = tostring(err) })
					print(string.format("  [FAIL] %s\n         %s", test.name, tostring(err)))
				end
			end
		end
	end
	table.clear(suites)
	currentBefore = { {} }
	return report
end

return TestKit
