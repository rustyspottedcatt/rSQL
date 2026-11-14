---
sidebar_position: 5
---

# Recipes

Copy, paste, rename the tables. All of these are in `examples/roblox` too.

## Player data in a shared DataStore

```lua
local db = rSQL.datastore(DataStoreService:GetDataStore("Game"))

db:exec([[
	CREATE TABLE IF NOT EXISTS Players (
		UserId   INTEGER PRIMARY KEY,
		Name     TEXT NOT NULL,
		Coins    INTEGER NOT NULL DEFAULT 0,
		LastSeen INTEGER
	)
]])

Players.PlayerAdded:Connect(function(player)
	local found = db:exec("SELECT Coins FROM Players WHERE UserId = ?", { player.UserId }).rows[1]
	if not found then
		db:exec("INSERT INTO Players (UserId, Name) VALUES (?, ?)", { player.UserId, player.Name })
	end
	player:SetAttribute("Coins", if found then found.Coins else 0)
end)

Players.PlayerRemoving:Connect(function(player)
	db:exec("UPDATE Players SET LastSeen = ? WHERE UserId = ?", { os.time(), player.UserId })
end)
```

## Leaderboard

```lua
task.spawn(function()
	while true do
		local top = db:exec("SELECT Name, Coins FROM Players ORDER BY Coins DESC LIMIT 10").rows
		for rank, row in top do
			print(rank, row.Name, row.Coins)
		end
		task.wait(30)
	end
end)
```

This is a full scan, so keep the interval in seconds, not frames.

## Buying something without going negative

```lua
local function buy(player, price: number): boolean
	local result = db:exec(
		"UPDATE Players SET Coins = Coins - ? WHERE UserId = ? AND Coins >= ?",
		{ price, player.UserId, price }
	)
	return result.affected == 1
end
```

The check and the subtraction run inside one `UpdateAsync`, so two purchases at once can't both spend the same coins.

## Inventory inside a profile

```lua
local db = rSQL.profile(profile)

db:exec([[
	CREATE TABLE IF NOT EXISTS Inventory (
		Item     TEXT PRIMARY KEY,
		Count    INTEGER NOT NULL DEFAULT 1,
		Equipped BOOLEAN NOT NULL DEFAULT false
	)
]])

local function give(item: string, amount: number)
	local updated = db:exec("UPDATE Inventory SET Count = Count + ? WHERE Item = ?", { amount, item })
	if updated.affected == 0 then
		db:exec("INSERT INTO Inventory (Item, Count) VALUES (?, ?)", { item, amount })
	end
end
```

## Loot table in memory

```lua
local loot = rSQL.memory()
loot:exec("CREATE TABLE Drops (Id INTEGER PRIMARY KEY AUTOINCREMENT, Item TEXT, Rarity TEXT, Weight REAL, MinLevel INTEGER)")
loot:exec([[
	INSERT INTO Drops (Item, Rarity, Weight, MinLevel) VALUES
		('Wooden Sword', 'common', 60, 1),
		('Iron Sword', 'rare', 25, 5),
		('Flame Staff', 'epic', 10, 10),
		('Crown', 'legendary', 1, 20)
]])

local function roll(level: number)
	local options = loot:exec("SELECT Item, Weight FROM Drops WHERE MinLevel <= ?", { level }).rows
	local total = 0
	for _, o in options do
		total += o.Weight
	end
	local pick = math.random() * total
	for _, o in options do
		pick -= o.Weight
		if pick <= 0 then
			return o.Item
		end
	end
	return options[#options].Item
end
```

## Stats per team

```sql
SELECT Team, COUNT(*) AS players, SUM(Coins) AS coins, ROUND(AVG(Level), 1) AS level
FROM Players
GROUP BY Team
ORDER BY coins DESC
```

## Read-only handle for an admin panel

```lua
local admin = rSQL.datastore(store, { permissions = "read" })
-- admin:exec("DROP TABLE Players") raises: rSQL: DROP isn't allowed on this database handle
```

## Trying things out without Studio

```bash
lune run scripts/rsql
lune run scripts/rsql -- --file examples/sql/tour.sql
lune run scripts/rsql -- --store dev.db.json
```

The shell prints results as tables and has `.tables`, `.schema <table>`, `.explain <query>` and `.stats`.
