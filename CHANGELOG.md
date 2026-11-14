# Changelog

All notable changes to rSQL. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.0.0]

A rewrite of the whole library. The 1.x API still works and 1.x data loads as it is; see [docs/migration.md](docs/migration.md).

### Fixed

- `CREATE TABLE` on an existing table replaced it with an empty one, wiping saved data. Through the 1.x API it now keeps the table and logs a warning; through the new API it's an error unless you write `IF NOT EXISTS`.
- Every value was stored as a string. Columns now have types and values keep them.
- `OR` in `WHERE` was treated as `AND`, and parentheses weren't supported.
- `LIKE` matched anywhere in the value (`'a%'` matched `banana`), and `_` and Lua pattern characters in the pattern weren't handled.
- A missing table returned an empty result instead of an error.

### Added

- `rSQL.datastore`, `rSQL.profile`, `rSQL.memory` and `rSQL.open`, all returning the same database handle with `exec`, `query`, `prepare`, `explain`, `tables` and `reshard`.
- Sharded DataStore layout: tables are split over several keys by primary key, so lookups read one shard and a table can grow past 4 MB. `db:reshard()` changes the shard count.
- New parser with `JOIN` / `LEFT JOIN`, `GROUP BY`, `HAVING`, `ORDER BY`, `LIMIT` / `OFFSET`, `DISTINCT`, `IN`, `BETWEEN`, `IS NULL`, `LIKE`, arithmetic, `||`, aggregates and scalar functions.
- `CREATE TABLE` with types, `PRIMARY KEY`, `AUTOINCREMENT`, `NOT NULL`, `UNIQUE` and `DEFAULT`; `ALTER TABLE ... RENAME COLUMN`; `SHOW TABLES`; `DESCRIBE`; `EXPLAIN`.
- `?` and `:name` parameters, and `rSQL.NULL`.
- Error messages with line, column, a caret under the problem, and suggestions for misspelled keywords, tables and columns.
- Permissions per handle (`"read"`, `"write"`, `"all"` or a table).
- Statement cache, `onQuery` hook, per-statement and per-handle stats.
- Retries with exponential back-off on DataStore throttling, and a clear error when a value is over the size limit.
- Tests that run under Lune, from the built Roblox place, and in Studio; benchmarks; a Studio playground; a SQL shell (`lune run scripts/rsql`).

### Removed

- The bundled evaera/promise. A small compatible promise is included for the 1.x API.

## [1.2.1] - 2024-12-27

### Added

- `LIKE` in conditions.

### Fixed

- Quote stripping and numeric comparisons in the DataStore backend.

## [1.2.0] - 2024-12-26

### Changed

- New SQL parsing based on a YACC-style grammar, with errors for missing tokens and unclosed quotes.

## [1.1.0] - 2024-12-26

### Added

- `ALTER TABLE`, `DROP TABLE` and `TRUNCATE`, with `allowAlterAdd`, `allowAlterDrop`, `allowDrop` and `allowTruncate` permissions.

## [1.0.0] - 2024-12-26

First release: `SELECT`, `INSERT`, `UPDATE` and `DELETE` on DataStores, ProfileService and DataKeep, with promise-based queries.

## [0.0.1] - 2024-12-25

Pre-release.

[2.0.0]: https://github.com/rustyspottedcatt/rSQL/compare/c5b711a...v2.0.0
