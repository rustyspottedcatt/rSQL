---
sidebar_position: 3
---

# Functions

This document provides detailed explanations and examples for each function in the `rSQL` module.

---

## `connect`

Establishes a connection to the DataStore with the provided configuration.

### **Syntax**
```lua
rSQL.connect(self: Types.DatastoreSQLConnection, datastore: Types.DataStore, config: Types.DatastoreSQLConfig): Types.TypedPromise<Types.DatastoreSQLConnection>
```

### **Parameters**
- `datastore (Types.DataStore)`: The DataStore instance to connect to.
- `config (Types.DatastoreSQLConfig)`: Configuration settings for the SQL module.

### **Returns**
- `Types.TypedPromise<Types.DatastoreSQLConnection>`: A promise that resolves to a SQL connection object.

### **Example**
```lua
local DataStoreService = game:GetService("DataStoreService")
local datastore = DataStoreService:GetDataStore("ExampleStore")

rSQL.connect(datastore, config):andThen(function(connection)
    print("Connected successfully to DataStore!")
    _G.dbConnection = connection
end):catch(function(err)
    warn("Connection failed: " .. err)
end)
```

---

## `connectToProfileService`

Establishes a connection to the Profile Service with the provided configuration.

### **Syntax**
```lua
rSQL.connectToProfileService(self: Types.ProfileSQLConnection, profilesTable: table, config: Types.DatastoreSQLConfig): Types.TypedPromise<Types.ProfileSQLConnection>
```

### **Parameters**
- `profilesTable (table)`: The table containing profile data.
- `config (Types.DatastoreSQLConfig)`: Configuration settings for the SQL module.

### **Returns**
- `Types.TypedPromise<Types.ProfileSQLConnection>`: A promise that resolves to a Profile SQL connection object.

### **Example**
```lua
local profilesTable = {}

rSQL.connectToProfileService(profilesTable, config):andThen(function(connection)
    print("Connected to Profile Service!")
    _G.profileConnection = connection
end):catch(function(err)
    warn("Connection failed: " .. err)
end)
```

---

## `query`

Executes an SQL query on the connected DataStore or ProfileService.

### **Syntax**
```lua
connection:query(query: Types.SQLQuery): Types.TypedPromise<Types.SQLQueryResult>
```

### **Parameters**
- `query (Types.SQLQuery)`: The SQL query string to execute.

### **Returns**
- `Types.TypedPromise<Types.SQLQueryResult>`: A promise resolving to the query result.

### **Example**
```lua
local sqlQuery = "SELECT * FROM Players WHERE Score > 50"
_G.dbConnection:query(sqlQuery):andThen(function(results)
    for _, player in ipairs(results) do
        print(player.Name, player.Score)
    end
end):catch(function(err)
    warn("Query failed: " .. err)
end)
```