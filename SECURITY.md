# Security

## Reporting a problem

If you find a way to read or change data you shouldn't be able to through rSQL, please don't open a public issue. Use GitHub's private vulnerability reporting on this repository (Security tab, "Report a vulnerability"). I'll reply within a week.

Supported versions: the latest 2.x release. 1.x gets no fixes; the 1.x API inside 2.x does.

## Using rSQL safely

### Never put player input into SQL text

```lua
-- unsafe: a name like  x' OR '1'='1  changes the query
db:exec(string.format("SELECT * FROM Players WHERE Name = '%s'", name))

-- safe: parameters are values, never parsed
db:exec("SELECT * FROM Players WHERE Name = ?", { name })
```

The 1.x quick start built queries with `string.format`. If your game still does, switching to parameters is the most important change to make.

### Keep it on the server

Don't expose a RemoteFunction that runs SQL a client sends, even read-only. Expose specific actions ("buy item 12") and build the query on the server.

### Use the least permission that works

```lua
local readOnly = rSQL.datastore(store, { permissions = "read" })
```

Admin panels, debug commands and anything that shows data should get a read-only handle.

### Know what's atomic

A statement whose rows live in one shard is one `UpdateAsync`, so it's atomic. A statement that spans shards commits one shard at a time, and `UNIQUE` on non-key columns can race between servers. For currency and items, change one row by primary key and do the check in the same statement:

```lua
db:exec("UPDATE Players SET Coins = Coins - ? WHERE UserId = ? AND Coins >= ?", { price, userId, price })
```

See [docs/advanced-usage.md](docs/advanced-usage.md) for the details.
