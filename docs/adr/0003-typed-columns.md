# 0003: Typed columns that convert on write

Accepted, 2.0.0.

## Context

1.x stored every value as a string. `Score + 1` was string concatenation or an error, `ORDER BY Score` sorted `"100"` before `"9"`, and people asked on the forum why their numbers came back as strings.

## Decision

Columns can declare a type (`INTEGER`, `REAL`, `TEXT`, `BOOLEAN`, `JSON`, `BLOB`, or none). Values are converted when written: `'42'` into an `INTEGER` column is stored as `42`, `'true'` into a `BOOLEAN` as `true`. Values that can't be converted are rejected with an error naming the table and column. Untyped columns accept anything, which keeps 1.x tables working.

Comparisons treat numeric strings as numbers, so old 1.x rows compare correctly next to new ones.

## Options I looked at

- **Strict types with no conversion.** Safer in theory, but rows inserted from SQL literals and from Luau values would behave differently, and old data would fail every comparison.
- **SQLite-style type affinity.** Close to what I did, but its rules (a `TEXT` column that holds numbers, and so on) are surprising for people who haven't used SQLite.

## Consequences

- Values round-trip with the type they went in with.
- One conversion per value written; reads don't convert.
- `JSON` and `BLOB` columns rely on what the backend can store. DataStores take tables and buffers; the docs say so.
