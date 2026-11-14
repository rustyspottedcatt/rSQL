--[[
	Test runner (Lune).

	    lune run tests/run              -- everything
	    lune run tests/run -- tokenizer -- only tests whose name contains "tokenizer"

	Discovers every *.spec.luau below tests/, runs it and exits non-zero on any
	failure so CI can gate on it.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local TestKit = require("./support/TestKit")

local filter: string? = nil
for _, arg in process.args do
	if arg ~= "--" then
		filter = arg
		break
	end
end

local function discover(dir: string, out: { string })
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, name in entries do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			discover(path, out)
		elseif string.match(name, "%.spec%.luau$") then
			table.insert(out, path)
		end
	end
end

local scriptDir = string.match(debug.info(1, "s"), "^(.*)[/\\]") or "."
local root = if fs.isDir("tests") then "tests" else scriptDir

local specs: { string } = {}
discover(root, specs)

local started = os.clock()
for _, path in specs do
	local relative = "./" .. string.sub(path, #root + 2, -6)
	local spec = require(relative) :: any
	spec(TestKit)
end
local report = TestKit.run(filter, os.clock)

print(string.format("\n%d passed, %d failed (%.2fs)", report.passed, report.failed, os.clock() - started))
if report.failed > 0 then
	print("\nFailures:")
	for _, f in report.failures do
		print("  - " .. f.name .. "\n      " .. f.err)
	end
	process.exit(1)
end
