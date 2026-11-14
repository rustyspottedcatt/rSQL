---
sidebar_position: 2
---

# Getting started

## Install

Pick one:

- Wally: add `rSQL = "rustyspottedcatt/rsql@2.0.0"` under `[dependencies]` and run `wally install`.
- Model file: download `rSQL.rbxm` from the [latest release](https://github.com/rustyspottedcatt/rSQL/releases) and drop it into `ReplicatedStorage`.
- Rojo: sync `src/` into `ReplicatedStorage` as a ModuleScript called `rSQL`.

rSQL has no dependencies. Use it from server scripts; DataStores aren't available on the client.

## Open a database

```lua
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local rSQL = require(ReplicatedStorage.rSQL)

-- shared by every server
local db = rSQL.datastore(DataStoreService:GetDataStore("Game"))

-- one player's profile (ProfileStore, ProfileService or DataKeep)
local playerDb = rSQL.profile(profile)

-- in memory, nothing saved
local items = rSQL.memory()
```

All three give you the same object with the same methods.

## Create a table

```lua
db:exec([[
	CREATE TABLE IF NOT EXISTS Players (
		UserId INTEGER PRIMARY KEY,
		Name   TEXT NOT NULL,
		Coins  INTEGER NOT NULL DEFAULT 0,
		Joined INTEGER
	)
]])
```

Run this on every server start. `IF NOT EXISTS` makes it do nothing when the table is already there.

Pick the primary key with care on DataStore tables: lookups by primary key are the cheap ones (one shard read). For player data that's almost always `UserId`.

## Read and write

```lua
db:exec("INSERT INTO Players (UserId, Name, Joined) VALUES (?, ?, ?)", { player.UserId, player.Name, os.time() })

local result = db:exec("SELECT Coins FROM Players WHERE UserId = ?", { player.UserId })
local coins = result.rows[1].Coins

db:exec("UPDATE Players SET Coins = Coins + ? WHERE UserId = ?", { 25, player.UserId })
```

Always pass player-provided values as parameters (`?`) instead of building the SQL string yourself. Parameters are never parsed as SQL, so a name like `x' OR '1'='1` is just a name.

`exec` runs on the calling thread and yields while DataStore calls are in flight, like any DataStore code. It raises an error if something goes wrong, so wrap it in `pcall` where a failure shouldn't stop the script.

## The playground

The repo has a place that shows all of this running:

```bash
rokit install
rojo build dev.project.json -o rSQL-Playground.rbxl
```

Open it, press Play and walk onto the yellow pad.

Next: [SQL reference](basic-usage.md).
