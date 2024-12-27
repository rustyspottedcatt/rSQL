---
sidebar_position: 5
---

# Templates

Here are some `rSQL` templates to kickstart your journey!

---

## Player score datastore with rSQL:

```lua
local PlayerDatastore: DataStore = game:GetService("DataStoreService"):GetDataStore("PlayerDatastore")
local Promise = require(game.ReplicatedStorage.Packages.promise)
local rSQL = require(game.ReplicatedStorage.Packages.rSQL)

-- Connect to the datastore with configuration
local DB_CONNECTION = rSQL:connect(PlayerDatastore, {
	allowInsert = true,
	allowCreate = true,
	allowOverwrite = false,
	allowSelect = true,
	allowUpdate = true,
}):expect()

-- Initialize the database
local function onInit()
	return Promise.new(function(resolve, reject)
		warn("[rSQL Server] Initializing Datastore")

		local createSuccess, createError = DB_CONNECTION:query("CREATE TABLE Players (ID, Name, Score)"):expect()

		if createSuccess then
			resolve()
		else
			reject(createError)
		end
	end)
end

-- Handle player joining
local function onPlayerJoined(player: Player)
	return Promise.new(function(resolve, reject)
		warn("[rSQL Server] Player joined:", player.Name)

		local playerId = player.UserId
		local query = string.format("SELECT * FROM Players WHERE ID = %d", playerId)
		local playerData = DB_CONNECTION:query(query):expect()
		
		print(playerData)

		if type(playerData) == "table" and #playerData > 0 then
			player:SetAttribute("Score", playerData[1].Score)
			resolve(playerData[1])
		else
			local insertQuery = string.format(
				"INSERT INTO Players (ID, Name, Score) VALUES (%d, '%s', %d)",
				playerId, player.Name, 0
			)
			local insertSuccess, insertError = DB_CONNECTION:query(insertQuery):expect()

			if insertSuccess then
				player:SetAttribute("Score", 0)
				resolve()
			else
				reject(insertError)
			end
		end
	end)
end

-- Handle player leaving
local function onPlayerLeaving(player: Player)
	return Promise.new(function(resolve, reject)
		local playerId = player.UserId
		local playerScore = player:GetAttribute("Score")

		if playerScore ~= nil then
			-- Build and execute the query
			local updateQuery = string.format(
				"UPDATE Players SET Score = %d WHERE ID = %d",
				playerScore, playerId
			)
			print("[DEBUG] Update Query:", updateQuery)

			local updateSuccess, updateError = DB_CONNECTION:query(updateQuery):expect()
			if updateSuccess then
				warn(string.format("[rSQL Server] Saved data for player %s (Score: %d)", player.Name, playerScore))
				resolve()
			else
				warn(string.format(
					"[rSQL Server] Failed to save data for player %s: %s",
					player.Name, tostring(updateError)
					))
				reject(updateError)
			end
		else
			warn("[rSQL Server] No 'Score' attribute found for player:", player.Name)
			reject("No score attribute")
		end
	end)
end


-- Initialize and hook up events
onInit():andThen(function()
	warn("[rSQL Server] Successfully initialized datastore!")

	game.Players.PlayerAdded:Connect(function(player)
		onPlayerJoined(player):catch(function(err)
			warn("[rSQL Server] Error during player join:", err)
		end)
	end)

	for _, player in ipairs(game.Players:GetPlayers()) do
		onPlayerJoined(player):catch(function(err)
			warn("[rSQL Server] Error during player join:", err)
		end)
	end

	game.Players.PlayerRemoving:Connect(function(player)
		onPlayerLeaving(player):catch(function(err)
			warn("[rSQL Server] Error during player leave:", err)
		end)
	end)
end):catch(function(err)
	error("[rSQL Server] Failed to initialize datastore:", err)
end)
```

## Basic Usage

```lua
local PlayerDatastore: DataStore = game:GetService("DataStoreService"):GetDataStore("PlayerDatastore")
local rSQL = require(game.ReplicatedStorage.Packages.rSQL)

-- Connect to the datastore with configuration
local DB_CONNECTION = rSQL:connect(PlayerDatastore, {
    allowInsert = true,  -- Allow inserting new data
    allowCreate = true,  -- Allow creating tables
    allowOverwrite = false -- Prevent overwriting data to ensure safety
}):expect()

-- Create a Players table
DB_CONNECTION:query("CREATE TABLE Players (ID, Name, Score)"):andThen(function()
    print("Table 'Players' created successfully.")

    -- Insert data for a sample player, John Doe
    DB_CONNECTION:query("INSERT INTO Players (ID, Name, Score) VALUES (123456789, 'John Doe', 100)"):andThen(function()
        print("Player data for 'John Doe' inserted successfully.")

        -- Fetch data for John Doe
        DB_CONNECTION:query("SELECT * FROM Players WHERE ID = 123456789"):andThen(function(result)
            print("Fetched data for John Doe:", result)
        end):catch(function(error)
            warn("Failed to fetch player data:", error)
        end)
    end):catch(function(error)
        warn("Failed to insert player data:", error)
    end)
end):catch(function(error)
    warn("Failed to create table:", error)
end)
```