---
sidebar_position: 2
---

# Getting Started with rSQL

Welcome to the **rSQL** module documentation. This guide will walk you through the setup and basic usage of the module.

---

## Installation

### Step 1: Download the Module

1. Download the `rSQL` module from the official repository or marketplace.
2. Place the module in your game’s `ReplicatedStorage` or another shared location.

### Step 2: Require the Module

Require the `rSQL` module in your scripts:

```lua
local rSQL = require(game.ReplicatedStorage.Packages.rSQL)
```

### Step 3: Configuration

Define the configuration for your SQL operations. Example:

```lua
local config = {
    allowCreate = true,
    allowDrop = true,
    allowInsert = true,
    allowSelect = true,
    allowUpdate = true,
    allowDelete = true,
}
```

---

## Setting Up a Table

To use `rSQL`, you need to define and manage tables. Tables in `rSQL` simulate database tables.

### Example: Creating a Table

```lua
local connection = rSQL:connect(testDatastore, config):expect() -- yields
connection:query("CREATE TABLE Players (Id, Name, Score)")
```

### Explanation:
- **`CREATE TABLE`**: Creates a new table.
- **`Players`**: Table name.
- **Columns**: `Id`, `Name`, and `Score` define the schema.

---

## Basic Queries

### Inserting Data
```lua
local result = connection:query("INSERT INTO Players (Id, Name, Score) VALUES (1, 'Carlos', 5000)"):expect()
```

### Selecting Data
```lua
local result = connection:query("SELECT Name, Score FROM Players WHERE Score > 1000"):expect()
```

### Updating Data
```lua
local result = connection:query("UPDATE Players SET Score = 6000 WHERE Id = 1"):expect()
```

### Deleting Data
```lua
local result = connection:query("DELETE FROM Players WHERE Id = 1"):expect()
```

---

## Next Steps

Once you’re comfortable with the basics, explore the following:

- [Basic Usage](/basic-usage.md)
- [Advanced Usage](/advanced-usage.md)


