# 0001: Shard DataStore tables by primary key

Accepted, 2.0.0.

## Context

1.x stored a whole table under one DataStore key. That has three problems:

- every query, even a lookup of one player, downloads the whole table
- a table can't grow past the 4 MB value limit
- every write rewrites the whole table, so all servers queue up on one key and share its throughput limits

## Decision

New tables are split into N shard keys (8 by default) plus a meta key that holds the schema, the shard count, a generation number and the next auto-increment id. A row lives in shard `hash32(primary key) % N`. Every write is an `UpdateAsync` on the shards it touches.

The 1.x single-key layout stays available, and is what the 1.x API uses for new tables, so old and new servers can share data during an update.

## Options I looked at

- **One key per row.** Lookups and writes would be as small as they get, but a scan becomes one request per row, `SHOW TABLES` and `COUNT(*)` need a separate index, and `ListKeysAsync` is slow and paged. Too expensive for the leaderboard-style queries people use rSQL for.
- **Range sharding** (keys sorted into ranges). Good for `ORDER BY key` and ranges, but needs rebalancing as tables grow and makes the common case, sequential user ids, write to the last shard every time.
- **OrderedDataStore for indexes.** Only stores integers, so it can't hold rows, and keeping it in sync is a second write that can fail on its own.

## Consequences

- Lookups by primary key read 1/N of the table. Scans still read every shard (N + 1 requests).
- Capacity is about N x 4 MB. `db:reshard()` moves a table to more shards by writing a new generation of keys and switching the meta key over, so a failed reshard leaves the old generation intact.
- A statement that touches several shards isn't atomic across them. Documented, and the recipes keep balance changes to one row.
- `UNIQUE` on non-key columns is checked before writing and can race. Documented; use the primary key for anything that must be unique.
