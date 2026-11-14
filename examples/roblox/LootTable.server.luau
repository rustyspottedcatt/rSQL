--[[
	A loot table as an in-memory SQL table: no DataStore, nothing saved.
	Useful for game data you query a lot (items, shops, drop tables).
	Disabled in the playground by default; enable it and press Run.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local rSQL = require(ReplicatedStorage.rSQL)

local loot = rSQL.memory()
loot:exec([[
	CREATE TABLE Loot (
		Id INTEGER PRIMARY KEY AUTOINCREMENT,
		Item TEXT NOT NULL,
		Rarity TEXT NOT NULL,
		Element TEXT,
		Weight REAL NOT NULL
	)
]])
loot:exec([[
	INSERT INTO Loot (Item, Rarity, Element, Weight) VALUES
		('Wooden Sword', 'common', NULL, 50),
		('Iron Shield', 'common', NULL, 30),
		('Fire Staff', 'rare', 'fire', 9),
		('Ice Staff', 'rare', 'ice', 9),
		('Storm Bow', 'epic', 'lightning', 1.5),
		('Dragon Egg', 'legendary', 'fire', 0.5)
]])

-- Weighted pick from whatever the query returns.
local function roll(sql: string, params: { any }?): string?
	local rows = loot:exec(sql, params).rows
	local total = 0
	for _, row in rows do
		total += row.Weight
	end
	local r = math.random() * total
	for _, row in rows do
		r -= row.Weight
		if r <= 0 then
			return row.Item
		end
	end
	return nil
end

print("any drop:", roll("SELECT Item, Weight FROM Loot"))
print("elemental drop:", roll("SELECT Item, Weight FROM Loot WHERE Element IN ('fire', 'ice')"))
print("rare or better:", roll("SELECT Item, Weight FROM Loot WHERE Rarity != ?", { "common" }))

local summary = loot:exec([[
	SELECT Rarity, COUNT(*) AS items, SUM(Weight) AS weight
	FROM Loot GROUP BY Rarity ORDER BY weight DESC
]])
for _, row in summary.rows do
	print(string.format("%-10s %d items, %.1f%% of drops", row.Rarity, row.items, row.weight))
end
