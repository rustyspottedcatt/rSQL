--[[
	Per-player inventory inside a ProfileStore / ProfileService / DataKeep
	profile. The profile library loads, session-locks and saves the data;
	rSQL just gives you SQL over the tables inside profile.Data.

	Disabled in the playground: it needs your profile library. Swap
	`loadProfile` for however your game gets a player's profile.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local rSQL = require(ReplicatedStorage.rSQL)

-- Replace with ProfileStore / ProfileService / DataKeep loading.
local function loadProfile(_player: Player)
	return { Data = {} }
end

Players.PlayerAdded:Connect(function(player)
	local profile = loadProfile(player)
	local db = rSQL.profile(profile)

	db:exec([[
		CREATE TABLE IF NOT EXISTS Inventory (
			Item TEXT PRIMARY KEY,
			Count INTEGER NOT NULL DEFAULT 1,
			Equipped BOOLEAN NOT NULL DEFAULT false
		)
	]])

	local function give(item: string, amount: number)
		local updated = db:exec("UPDATE Inventory SET Count = Count + ? WHERE Item = ?", { amount, item })
		if updated.affected == 0 then
			db:exec("INSERT INTO Inventory (Item, Count) VALUES (?, ?)", { item, amount })
		end
	end

	give("Apple", 3)
	give("Apple", 2)
	give("Sword", 1)
	db:exec("UPDATE Inventory SET Equipped = true WHERE Item = 'Sword'")

	for _, row in db:exec("SELECT Item, Count, Equipped FROM Inventory ORDER BY Item").rows do
		print(player.Name, row.Item, row.Count, row.Equipped)
	end
end)
