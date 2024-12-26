---

sidebar_position: 2
---

# Getting Started

Follow these steps to integrate and use the `rSQL` module in your Roblox game project.

---

### Prerequisites

1. **Dependencies**:
   Ensure the following libraries are included in your Roblox project:
   - [`Promise`](https://github.com/evaera/roblox-lua-promise) – A robust promise implementation for Lua.
   - [`Signal`](https://github.com/evaera/roblox-lua-signal) – A library for creating event-driven workflows.

2. **DataStoreService Permissions**:
   - Enable **Studio Access to API Services** in Roblox Studio settings to allow DataStore usage during testing.

---

### Step 1: Installation

1. Clone or download the `rSQL` module along with its dependencies into your project.
2. Organize the module in the following structure:
   ```
   Packages/
   ├── rSQL/
   │   ├── init.luau
   │   ├── lib/
   │   │   ├── types.luau
   │   ├── components/
   │   │   ├── DatastoreSQL.luau
   │   │   ├── ProfileSQL.luau
   ```

3. Reference the module in your scripts:
   ```lua
   local rSQL = require(game:GetService("ReplicatedStorage").Packages.rSQL)
   ```

---

### Step 2: Configuration

Define a configuration table to control the behavior of the `rSQL` module. Below is an example configuration:

```lua
local config = {
    allowOverwrite = true,
    allowInsert = true,
    allowSelect = true,
    allowUpdate = true,
    allowDelete = true,
    allowCreate = true,
    allowDrop = false,
    allowTruncate = false,
    allowAlter = false,
    allowTransaction = false,
}
```

---

### Step 3: Connecting to DataStore

Use the `connect` function to establish a connection to your DataStore:

```lua
local DataStoreService = game:GetService("DataStoreService")
local datastore = DataStoreService:GetDataStore("ExampleStore")

rSQL:connect(datastore, config)
    :andThen(function(connection)
        print("Connected to DataStore!")
        -- Save the connection for future queries
        _G.dbConnection = connection
    end)
    :catch(function(error)
        warn("Failed to connect: " .. error)
    end)
```

---

### Step 4: Running Queries

After establishing a connection, use SQL-like commands to manage your data.

#### Creating a Table
```lua
_G.dbConnection:query("CREATE TABLE Players (ID, Name, Score)")
    :andThen(function(result)
        print("Table created successfully!")
    end)
    :catch(function(error)
        warn("Failed to create table: " .. error)
    end)
```

#### Inserting Data
```lua
_G.dbConnection:query("INSERT INTO Players (Name, Score) VALUES ('Player1', 100)")
    :andThen(function(result)
        print("Data inserted successfully!")
    end)
    :catch(function(error)
        warn("Failed to insert data: " .. error)
    end)
```

#### Retrieving Data
```lua
_G.dbConnection:query("SELECT * FROM Players WHERE Score > 50")
    :andThen(function(results)
        for _, player in ipairs(results) do
            print("Player:", player.Name, "Score:", player.Score)
        end
    end)
    :catch(function(error)
        warn("Failed to retrieve data: " .. error)
    end)
```

#### Updating Data
```lua
_G.dbConnection:query("UPDATE Players SET Score = 200 WHERE Name = 'Player1'")
    :andThen(function(result)
        print("Data updated successfully!")
    end)
    :catch(function(error)
        warn("Failed to update data: " .. error)
    end)
```

#### Deleting Data
```lua
_G.dbConnection:query("DELETE FROM Players WHERE Score < 100")
    :andThen(function(result)
        print("Data deleted successfully!")
    end)
    :catch(function(error)
        warn("Failed to delete data: " .. error)
    end)
```

---

### Step 5: Connecting to ProfileService

If you’re managing player profiles, use the `connectToProfileService` method instead:

```lua
local profilesTable = {}

rSQL:connectToProfileService(profilesTable, config)
    :andThen(function(connection)
        print("Connected to ProfileService!")
        -- Save the connection for future queries
        _G.profileConnection = connection
    end)
    :catch(function(error)
        warn("Failed to connect: " .. error)
    end)
```

ProfileService queries follow the same format as DataStore queries.