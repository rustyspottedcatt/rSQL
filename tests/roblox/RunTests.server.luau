--[[
	Runs the full test suite inside Roblox Studio.

	Build and open the test place, then press Run (F8) or Play:

	    rojo build test.project.json -o rSQL-Tests.rbxl

	The place mirrors the repository layout (ServerScriptService.rSQLDev.src
	and .tests), so every spec's relative string requires resolve exactly as
	they do under Lune. Results go to the Output window. The final line is
	`[rSQL tests] PASS ...` or `[rSQL tests] FAIL ...`, and the same outcome is
	written to the `rSQLTests` attribute on Workspace for tooling.
]]

local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local testsFolder = script.Parent.Parent
local TestKit = require(testsFolder.support.TestKit)

-- Optional name filter: set a `Filter` string attribute on this script.
local filter = script:GetAttribute("Filter")

local specs: { ModuleScript } = {}
for _, descendant in testsFolder:GetDescendants() do
	if descendant:IsA("ModuleScript") and string.match(descendant.Name, "%.spec$") then
		table.insert(specs, descendant)
	end
end
table.sort(specs, function(a, b)
	return a:GetFullName() < b:GetFullName()
end)

workspace:SetAttribute("rSQLTests", "running")
print(string.format("[rSQL tests] running %d spec files in Studio", #specs))

local started = os.clock()
for _, spec in specs do
	local ok, err = pcall(function()
		(require(spec) :: any)(TestKit)
	end)
	if not ok then
		warn(string.format("[rSQL tests] could not load %s: %s", spec:GetFullName(), tostring(err)))
	end
end

local report = TestKit.run(if type(filter) == "string" and filter ~= "" then filter else nil, os.clock)
local summary = string.format("%d passed, %d failed in %.1fs", report.passed, report.failed, os.clock() - started)

if report.failed > 0 then
	for _, failure in report.failures do
		warn("[rSQL tests] " .. failure.name .. "\n    " .. failure.err)
	end
	warn("[rSQL tests] FAIL " .. summary)
	workspace:SetAttribute("rSQLTests", "FAIL " .. summary)
else
	print("[rSQL tests] PASS " .. summary)
	workspace:SetAttribute("rSQLTests", "PASS " .. summary)
end
