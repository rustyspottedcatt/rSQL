--[[
	The 1.x quick start, unchanged, running on rSQL 2.x.

	It runs CREATE TABLE on every server start. In 1.x that replaced the
	table with an empty one, wiping every saved score. 2.x keeps the data
	and prints a warning instead.

	Disabled in the playground by default. Needs Studio API access.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local rSQL = require(ReplicatedStorage.rSQL)

local sqlConnection = rSQL:connect(DataStoreService:GetDataStore("PlayerDatastore"), {
	allowInsert = true,
	allowCreate = true,
	allowOverwrite = false,
	allowSelect = true,
	allowUpdate = true,
}):expect()

sqlConnection:query("CREATE TABLE Players (ID, Name, Score)"):expect()

Players.PlayerAdded:Connect(function(player)
	local results = sqlConnection:query(string.format("SELECT * FROM Players WHERE ID = %d", player.UserId)):expect()
	if #results == 0 then
		sqlConnection
			:query(
				string.format("INSERT INTO Players (ID, Name, Score) VALUES (%d, '%s', 0)", player.UserId, player.Name)
			)
			:expect()
	end
	player:SetAttribute("Score", if results[1] then tonumber(results[1].Score) else 0)
end)

Players.PlayerRemoving:Connect(function(player)
	sqlConnection
		:query(
			string.format(
				"UPDATE Players SET Score = %d WHERE ID = %d",
				player:GetAttribute("Score") or 0,
				player.UserId
			)
		)
		:expect()
end)
