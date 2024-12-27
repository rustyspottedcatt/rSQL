---
sidebar_position: 1
---

# Introduction to rSQL

Welcome to the **rSQL** module documentation! This section provides an overview of the module's purpose, core concepts, and unique features.

---

## What is rSQL?

`rSQL` is a powerful SQL-inspired library for Roblox game development. It simplifies data management by offering structured queries and robust integration with Roblox DataStores. Inspired by relational databases, `rSQL` enables developers to perform complex data manipulations effortlessly.

---

## Why Use rSQL?

Managing game data is a challenging task, especially with large datasets or complex relationships. `rSQL` addresses these challenges by providing:

- **SQL-Like Syntax**: Familiar and intuitive commands for developers.
- **Data Persistence**: Seamless integration with Roblox DataStores for storing and retrieving data.
- **Flexibility**: Support for creating, modifying, and querying virtual tables.
- **Scalability**: Designed for high performance and large datasets.
- **Error Handling**: Clear debugging tools and promise-based error management.

---

## Key Features

### 1. Virtual Tables
Define and manage tables as abstractions over Roblox DataStores.

### 2. SQL-Inspired Queries
Use SQL-like commands such as `SELECT`, `INSERT`, `UPDATE`, and `DELETE`.

Example:
```lua
connection:query("SELECT Name, Score FROM Players WHERE Score > 1000 ORDER BY Score DESC")
```

### 3. Advanced Query Capabilities
Support for:
- Filtering (`WHERE` clauses)
- Sorting (`ORDER BY`)
- Aggregations (`COUNT`, `SUM`)

### 4. Integration with Roblox DataStores
Easily connect `rSQL` to Roblox's persistent storage:
```lua
rSQL:connect(DataStoreInstance, config)
```

### 5. Debugging and Tracing
Enable debugging to log SQL queries and errors:
```lua
rSQL.enableDebugging(true)
```

### 6. Promise-Based Operations
Leverage promises for asynchronous queries and seamless error handling.

---

## Philosophy

`rSQL` is built on the principle of making data management as simple as possible without sacrificing flexibility or power. By abstracting complex operations, it enables developers to focus on creating engaging gameplay experiences.

---

## Next Steps

Dive deeper into the details:

- [Getting Started](/getting-started)
- [Basic Usage](/basic-usage.md)
- [Advanced Usage](/advanced-usage.md)

`rSQL` is here to make your data work for you!

