---
sidebar_position: 1
---

# About

The `rSQL` module is a robust SQL-like data handling library designed for Roblox developers. Built on top of Roblox's `DataStoreService` and `ProfileService`, it simplifies data management by providing SQL-like operations, robust type-checking, and promise-based asynchronous workflows.

## Why choose rSQL?

Data management on Roblox can be cumbersome with `DataStoreService` and `ProfileService`, especially when scaling your game or creating complex data-driven mechanics. The `rSQL` module aims to bridge this gap by introducing familiar SQL-like commands and workflows.

### Key Benefits

- **Simplifies Development**: Provides SQL-like commands that reduce the complexity of working directly with Roblox services.
- **Asynchronous Workflow**: Makes use of promises to handle asynchronous operations, reducing callback hell and improving error management.
- **Customizable Configuration**: Fully configurable options for controlling SQL operations, like allowing or disallowing specific commands (e.g., CREATE, DROP, INSERT).
- **Error Handling**: Provides detailed error messages with tracebacks to simplify debugging.
- **Type-Safe Operations**: Built with strict typing to ensure safer and more predictable operations, making it ideal for large, collaborative projects.

---

## Features Overview

### SQL-like Operations
With `rSQL`, you can perform:
- **Data Manipulation**: `INSERT`, `SELECT`, `UPDATE`, and `DELETE`.
- **Schema Management**: `CREATE`, `DROP`, and `TRUNCATE` tables.
- **Advanced Queries**: Parse and execute SQL-like strings with conditions and clauses.

### DataStore and ProfileService Integration
- Seamless support for both `DataStoreService` and `ProfileService`.
- Abstracts away the boilerplate code required for data persistence and retrieval.

### Promises for Async Operations
All methods return promises, enabling clean and readable asynchronous workflows:
```lua
local rSQL = require(script.rSQL)

rSQL.connect(datastore, config)
    :andThen(function(connection)
        print("Connected successfully!")
        return connection:query("INSERT INTO Players (Name, Score) VALUES ('Player1', 100)")
    end)
    :catch(function(err)
        warn("Error: " .. err)
    end)
