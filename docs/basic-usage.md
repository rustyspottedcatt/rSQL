---
sidebar_position: 3
---

# Basic Usage

This section introduces the fundamental concepts and operations of `rSQL`. Learn how to define tables, perform CRUD operations, and query data effectively.

---

## Establishing a Connection

Before using `rSQL`, establish a connection to a DataStore. This connection serves as the interface for all operations.

### Example:
```lua
local DataStoreService = game:GetService("DataStoreService")
local rSQL = require(game.ReplicatedStorage.Packages.rSQL)

local testDatastore = DataStoreService:GetDataStore("TestDatabase")

local config = {
    allowCreate = true,
    allowInsert = true,
    allowSelect = true,
    allowUpdate = true,
    allowDelete = true,
}

local connection = rSQL:connect(testDatastore, config)
connection:andThen(function()
    print("Connection established!")
end):catch(function(err)
    warn("Failed to connect:", err)
end)
```

---

## Creating a Table

Tables in `rSQL` define the structure of your data. Use `CREATE TABLE` to define schemas.

### Example:
```lua
connection:query("CREATE TABLE Players (Id INTEGER PRIMARY KEY, Name TEXT, Score INTEGER)"):andThen(function(result)
    print("Table created successfully!", result)
end):catch(function(err)
    warn("Error creating table:", err)
end)
```

### Explanation:
- **`CREATE TABLE`**: SQL command to define a new table.
- **Columns**: Define each column's name and data type (e.g., `Id INTEGER`, `Name TEXT`).

---

## Inserting Data

Use the `INSERT INTO` command to add rows to a table.

### Example:
```lua
connection:query("INSERT INTO Players (Id, Name, Score) VALUES (1, 'Carlos', 5000)"):andThen(function(result)
    print("Data inserted successfully!", result)
end):catch(function(err)
    warn("Error inserting data:", err)
end)
```

---

## Querying Data

Retrieve data from your tables using the `SELECT` command.

### Example:
```lua
connection:query("SELECT Name, Score FROM Players WHERE Score > 3000 ORDER BY Score DESC"):andThen(function(results)
    for _, row in pairs(results) do
        print(row.Name, row.Score)
    end
end):catch(function(err)
    warn("Error querying data:", err)
end)
```

### Explanation:
- **`SELECT`**: SQL command to retrieve data.
- **`WHERE`**: Filter results based on conditions.
- **`ORDER BY`**: Sort results.

---

## Updating Data

Modify existing rows using the `UPDATE` command.

### Example:
```lua
connection:query("UPDATE Players SET Score = 6000 WHERE Id = 1"):andThen(function(result)
    print("Data updated successfully!", result)
end):catch(function(err)
    warn("Error updating data:", err)
end)
```

---

## Deleting Data

Remove rows from a table using the `DELETE` command.

### Example:
```lua
connection:query("DELETE FROM Players WHERE Id = 1"):andThen(function(result)
    print("Data deleted successfully!", result)
end):catch(function(err)
    warn("Error deleting data:", err)
end)
```

---

## Combining Operations

You can chain operations to perform complex workflows.

### Example:
```lua
connection:query("CREATE TABLE Test (Id INTEGER PRIMARY KEY, Value INTEGER)")
    :andThen(function()
        return connection:query("INSERT INTO Test (Id, Value) VALUES (1, 100)")
    end)
    :andThen(function()
        return connection:query("SELECT * FROM Test")
    end)
    :andThen(function(results)
        for _, row in pairs(results) do
            print(row.Id, row.Value)
        end
    end)
    :catch(function(err)
        warn("Error during operations:", err)
    end)
```

---

## Next Steps

Now that you understand the basics, proceed to explore:

- [Advanced Usage](/advanced-usage.md)

`rSQL` offers extensive flexibility and power to manage your game's data.

