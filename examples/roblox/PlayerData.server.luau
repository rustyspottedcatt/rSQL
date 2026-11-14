--[[
	Coins and a live leaderboard, stored with rSQL.

	Step on the glowing pad to earn coins. Each player is one row in a
	Players table; the board shows the top 5 with ORDER BY ... LIMIT.

	Uses a real DataStore when Studio has API access ("Enable Studio Access
	to API Services"), and an in-memory database otherwise, so the place
	works either way.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local rSQL = require(ReplicatedStorage.rSQL)

local function openDatabase()
	local ok, store = pcall(function()
		local s = DataStoreService:GetDataStore("rSQL_Playground")
		s:GetAsync("__probe") -- fails fast without API access
		return s
	end)
	if ok then
		print("[PlayerData] using DataStore rSQL_Playground")
		return rSQL.datastore(store, { shards = 8 })
	end
	warn("[PlayerData] no DataStore access in this session, using an in-memory database")
	return rSQL.memory()
end

local db = openDatabase()
db:exec([[
	CREATE TABLE IF NOT EXISTS Players (
		UserId   INTEGER PRIMARY KEY,
		Name     TEXT NOT NULL,
		Coins    INTEGER NOT NULL DEFAULT 0,
		Visits   INTEGER NOT NULL DEFAULT 0
	)
]])

local findPlayer = db:prepare("SELECT Coins, Visits FROM Players WHERE UserId = ?")
local addCoins = db:prepare("UPDATE Players SET Coins = Coins + ? WHERE UserId = ?")
local topPlayers = db:prepare("SELECT Name, Coins FROM Players ORDER BY Coins DESC, Name LIMIT 5")

local function setupLeaderstats(player: Player, coins: number)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local value = Instance.new("IntValue")
	value.Name = "Coins"
	value.Value = coins
	value.Parent = stats
	stats.Parent = player
end

Players.PlayerAdded:Connect(function(player)
	local row = findPlayer:run({ player.UserId }).rows[1]
	if row then
		db:exec("UPDATE Players SET Visits = Visits + 1, Name = ? WHERE UserId = ?", { player.Name, player.UserId })
	else
		db:exec("INSERT INTO Players (UserId, Name, Visits) VALUES (?, ?, 1)", { player.UserId, player.Name })
		row = { Coins = 0 }
	end
	setupLeaderstats(player, row.Coins)
end)

-- Coin pad -----------------------------------------------------------------------------

local pad = workspace:WaitForChild("CoinPad") :: BasePart
local cooldown: { [Player]: number } = {}

pad.Touched:Connect(function(hit)
	local player = Players:GetPlayerFromCharacter(hit.Parent)
	if not player or (cooldown[player] and os.clock() - cooldown[player] < 1) then
		return
	end
	cooldown[player] = os.clock()
	addCoins:run({ 10, player.UserId })
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins") :: IntValue?
	if coins then
		coins.Value = findPlayer:run({ player.UserId }).rows[1].Coins
	end
end)

Players.PlayerRemoving:Connect(function(player)
	cooldown[player] = nil
end)

-- Leaderboard ----------------------------------------------------------------------------

local board = workspace:WaitForChild("Leaderboard") :: BasePart
local gui = Instance.new("SurfaceGui")
gui.Face = Enum.NormalId.Front
gui.PixelsPerStud = 40
gui.Parent = board
local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(1, 1)
label.BackgroundColor3 = Color3.fromRGB(26, 26, 25)
label.TextColor3 = Color3.fromRGB(240, 239, 236)
label.Font = Enum.Font.Code
label.TextScaled = true
label.TextXAlignment = Enum.TextXAlignment.Left
label.Parent = gui

while true do
	local lines = { "SELECT Name, Coins FROM Players", "ORDER BY Coins DESC LIMIT 5", "" }
	for i, row in topPlayers:run().rows do
		table.insert(lines, string.format("%d. %-14s %6d", i, row.Name, row.Coins))
	end
	label.Text = table.concat(lines, "\n")
	task.wait(2)
end
