# 0005: Cache table metadata for one statement only

Accepted, 2.0.0.

## Context

Every sharded-table operation needs the table's meta key (schema, shard count, generation). Without a cache, a key lookup was 3 reads: one to find the table, one for the meta inside the planner, one for the shard. With a long-lived cache, a server would keep using an old schema or shard count after another server ran `ALTER TABLE` or `db:reshard()`, and could write rows to keys nobody reads anymore.

## Decision

The DataStore adapter caches meta for the length of one statement. `Database` calls `beginStatement()` before running and `endStatement()` after, and every write to the meta key drops the cached copy.

## Options I looked at

- **Cache with a time limit.** Cuts reads further, but any limit is a window where two servers disagree about the schema. A wrong shard count means writing rows where lookups won't find them.
- **MessagingService invalidation.** Delivery isn't guaranteed, and it adds a service dependency for a small saving.

## Consequences

- A key lookup is 2 reads (meta, shard) instead of 3.
- Schema changes are visible to every server from its next statement.
- A statement still pays one meta read. For read-heavy data that rarely changes, `rSQL.memory()` with a periodic refresh is cheaper.
