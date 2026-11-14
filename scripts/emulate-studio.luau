--[[
	Runs the test suite from the Rojo-built Roblox place, the way Studio would.

	    lune run scripts/emulate-studio

	1. Builds test.project.json and dev.project.json with Rojo.
	2. Opens the .rbxl files with @lune/roblox and executes ModuleScript sources
	   straight from the instance tree.
	3. Resolves every `require` with Roblox's rules: instance arguments, and
	   string paths starting with `./` (the script's parent), `../` (its
	   grandparent) or `@self` (the script itself). Anything else, such as
	   `@lune/...`, fails exactly as it would in Studio.
	4. Gives every module Roblox-style globals (`game`, `workspace`, `script`,
	   `task`), so the library takes its Roblox code path, including yielding
	   to the scheduler through `task.wait`.
	5. Loads rSQL from the playground place and runs a few statements through
	   both the 2.x API and the 1.x API against an in-memory DataStore.

	This catches layout, require and platform-detection problems without
	Studio. It is not the Roblox engine: real DataStores, players and
	networking are not exercised. Use
	tests/roblox/RunTests.server.luau in Studio for the real thing.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local BUILD_DIR = "build"

local function build(project: string, output: string)
	local result = process.exec("rojo", { "build", project, "--output", output })
	if not result.ok then
		error(string.format("rojo build %s failed:\n%s%s", project, result.stdout, result.stderr))
	end
end

if not fs.isDir(BUILD_DIR) then
	fs.writeDir(BUILD_DIR)
end
build("test.project.json", BUILD_DIR .. "/rSQL-Tests.rbxl")
build("dev.project.json", BUILD_DIR .. "/rSQL-Playground.rbxl")

-- Module system with Roblox semantics -------------------------------------------

type Loader = {
	cache: { [any]: any },
	game: any,
	require: (self: Loader, from: any, target: any) -> any,
}

local function resolve(from: any, path: string): any
	local segments = string.split(path, "/")
	local head = segments[1]
	local node: any
	if head == "." then
		node = from.Parent
	elseif head == ".." then
		node = from.Parent and from.Parent.Parent
	elseif head == "@self" then
		node = from
	else
		error(
			string.format(
				"%s: require(%q) is not a valid Roblox path (must start with ./, ../ or @self)",
				from:GetFullName(),
				path
			)
		)
	end
	for i = 2, #segments do
		local segment = segments[i]
		if node == nil then
			break
		end
		if segment == ".." then
			node = node.Parent
		elseif segment ~= "" and segment ~= "." then
			node = node:FindFirstChild(segment)
		end
	end
	if node == nil then
		error(string.format("%s: require(%q) does not resolve to an instance", from:GetFullName(), path))
	end
	if not node:IsA("ModuleScript") then
		error(
			string.format(
				"%s: require(%q) resolves to a %s, not a ModuleScript",
				from:GetFullName(),
				path,
				node.ClassName
			)
		)
	end
	return node
end

local function newLoader(game: any): Loader
	local loader = { cache = {}, game = game } :: Loader
	local loading: { [any]: boolean } = {}

	function loader:require(from: any, target: any): any
		local module = if type(target) == "string" then resolve(from, target) else target
		-- Lune returns a fresh userdata per lookup, so key the cache by path
		-- (Roblox caches by instance identity; paths are unique in this tree).
		local key = module:GetFullName()
		if self.cache[key] ~= nil then
			return self.cache[key]
		end
		if loading[key] then
			error("cyclic require of " .. key)
		end
		loading[key] = true
		local env = {
			game = game,
			workspace = game:GetService("Workspace"),
			script = module,
			task = task,
		}
		env.require = function(arg: any)
			return loader:require(module, arg)
		end
		local chunk = luau.load(module.Source, { debugName = module:GetFullName(), environment = env })
		local result = chunk()
		loading[key] = nil
		self.cache[key] = result
		return result
	end

	return loader
end

-- 1. Test suite ----------------------------------------------------------------------

local testPlace = roblox.deserializePlace(fs.readFile(BUILD_DIR .. "/rSQL-Tests.rbxl"))
local dev = testPlace:GetService("ServerScriptService"):FindFirstChild("rSQLDev")
assert(dev, "test place is missing ServerScriptService.rSQLDev")
local tests = dev:FindFirstChild("tests")

local loader = newLoader(testPlace)
local TestKit = loader:require(dev, tests.support.TestKit)

local specs = {}
for _, d in tests:GetDescendants() do
	if d:IsA("ModuleScript") and string.match(d.Name, "%.spec$") then
		table.insert(specs, d)
	end
end
table.sort(specs, function(a, b)
	return a:GetFullName() < b:GetFullName()
end)
print(string.format("[emulate-studio] %d spec modules from %s", #specs, BUILD_DIR .. "/rSQL-Tests.rbxl"))

local started = os.clock()
for _, spec in specs do
	loader:require(dev, spec)(TestKit)
end
local filter: string? = nil
for _, arg in process.args do
	if arg ~= "--" then
		filter = arg
		break
	end
end
local report = TestKit.run(filter, os.clock)

-- 2. The library from the playground place, both APIs ------------------------------------

local playground = roblox.deserializePlace(fs.readFile(BUILD_DIR .. "/rSQL-Playground.rbxl"))
local playLoader = newLoader(playground)
local storage = playground:GetService("ServerStorage")
local rSQL = playLoader:require(storage, playground:GetService("ReplicatedStorage").rSQL)
local runtime = rSQL.Platform.runtime()

-- minimal GlobalDataStore: enough for UpdateAsync-based writes
local fakeStore = { data = {} }
function fakeStore:GetAsync(key)
	return self.data[key]
end
function fakeStore:UpdateAsync(key, fn)
	local new = fn(self.data[key])
	if new ~= nil then
		self.data[key] = new
	end
	return new
end
function fakeStore:RemoveAsync(key)
	self.data[key] = nil
end

local db = rSQL.datastore(fakeStore, { shards = 4 })
db:exec("CREATE TABLE Players (UserId INTEGER PRIMARY KEY, Coins INTEGER DEFAULT 0)")
db:exec("INSERT INTO Players (UserId) VALUES (1), (2)")
db:exec("UPDATE Players SET Coins = Coins + 25 WHERE UserId = ?", { 2 })
local coins = db:exec("SELECT Coins FROM Players WHERE UserId = 2").rows[1].Coins

local legacy = rSQL:connect(fakeStore, { allowCreate = true, allowInsert = true, allowSelect = true }):expect()
legacy:query("CREATE TABLE Scores (ID, Score)"):expect()
legacy:query("INSERT INTO Scores (ID, Score) VALUES ('1', '500')"):expect()
local legacyRows = legacy:query("SELECT * FROM Scores"):expect()

print(string.format("\n[emulate-studio] platform=%s, coins=%s, 1.x rows=%d", runtime, tostring(coins), #legacyRows))

local smokeOk = runtime == "roblox" and coins == 25 and #legacyRows == 1
print(
	string.format(
		"\n[emulate-studio] %d passed, %d failed, playground smoke test %s (%.1fs)",
		report.passed,
		report.failed,
		if smokeOk then "ok" else "FAILED",
		os.clock() - started
	)
)
if report.failed > 0 or not smokeOk then
	for _, f in report.failures do
		print("  - " .. f.name .. "\n      " .. f.err)
	end
	process.exit(1)
end
