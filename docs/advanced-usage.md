---
sidebar_position: 4
---

# Advanced Usage

This section demonstrates advanced applications of the `rSQL` module, showing how to integrate complex SQL-like operations into your Roblox game.

---

## Custom Data Manipulation

Utilize `rSQL` to handle intricate data operations, such as selective updates and dynamic queries.

### Example: Bulk Data Update
Update player scores conditionally:

```lua
local query = "UPDATE Players SET Score = Score + 100 WHERE Score < 5000"
connection:query(query):andThen(function(result)
    print("Scores updated successfully.")
end):catch(function(err)
    warn("Failed to update scores:", err)
end)
```

---

## Error Handling with Promises

Handle errors effectively using `Promise`-based patterns. This ensures you can catch and address issues promptly.

### Example: Query Execution with Error Handling

```lua
connection:query("SELECT * FROM Players WHERE Age < 18")
    :andThen(function(results)
        for _, player in ipairs(results) do
            print(player.Name, player.Age)
        end
    end)
    :catch(function(err)
        warn("Query failed:", err)
    end)
```

---

## Integrating with Profile Service

`rSQL` can interface with the Profile Service to handle player data seamlessly.

### Example: Creating and Using Profiles

```lua
local profilesTable = {} -- Simulated profile data
local config = {
    allowCreate = true,
    allowInsert = true,
    allowSelect = true,
    allowUpdate = true,
}

rSQL:connectToProfileService(profilesTable, config):andThen(function(connection)
    print("Connected to Profile Service.")

    -- Create a table for profiles
    connection:query("CREATE TABLE PlayerProfiles (Id INTEGER PRIMARY KEY, Name TEXT, Age INTEGER)")

    -- Insert a new profile
    connection:query("INSERT INTO PlayerProfiles (Id, Name, Age) VALUES (1, 'Carlos', 25)")

    -- Query profiles
    connection:query("SELECT * FROM PlayerProfiles")
        :andThen(function(results)
            for _, profile in ipairs(results) do
                print(profile.Name, profile.Age)
            end
        end)
        :catch(function(err)
            warn("Failed to fetch profiles:", err)
        end)
end):catch(function(err)
    warn("Failed to connect to Profile Service:", err)
end)
```

---

## Advanced Query Composition

Construct dynamic queries programmatically based on runtime conditions.

### Example: Dynamic WHERE Clause

```lua
local ageLimit = 20
local query = string.format("SELECT * FROM Players WHERE Age > %d", ageLimit)
connection:query(query):andThen(function(results)
    for _, player in ipairs(results) do
        print(player.Name, player.Age)
    end
end):catch(function(err)
    warn("Query failed:", err)
end)
```

---

## Best Practices

- **Validate Queries**: Ensure your queries are correctly formatted to avoid runtime errors.
- **Error Logging**: Use `catch` blocks to log and debug issues.
- **Optimize Conditions**: Minimize data filtering in queries for better performance.

---

With these advanced techniques, you can leverage the full power of `rSQL` to manage complex data operations in your Roblox game!

