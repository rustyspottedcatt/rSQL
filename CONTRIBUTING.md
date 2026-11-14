# Contributing

Bug reports, fixes and new SQL features are welcome. Open an issue first for anything bigger than a small fix so we can agree on the shape of it.

## Setup

```bash
rokit install        # lune, rojo, stylua, selene, luau-lsp, wally at pinned versions
lune run tests/run   # should print "N passed, 0 failed"
```

You don't need Roblox Studio for most work. The engine runs under Lune, and `lune run scripts/emulate-studio` runs the suite from the Rojo-built place with Roblox's `require` rules.

## Before you open a pull request

```bash
stylua src tests scripts bench examples
selene src tests
luau-lsp analyze --platform=standard --definitions=types/globals.d.luau --ignore="src/**/*.server.luau" src
lune run tests/run
lune run scripts/emulate-studio
```

CI runs the same steps.

## Where things go

- New SQL syntax: `src/SQL/Lexer.luau` and `src/SQL/Parser.luau`, the node in `src/SQL/Ast.luau`, a parser test in `tests/unit/Sql.spec.luau`.
- How it runs: `src/Engine/Executor.luau` (statements) or `src/Engine/Expression.luau` (operators and functions), with a test in `tests/unit/Engine.spec.luau`.
- Storage behavior: `src/Storage/`, tested in `tests/integration/Storage.spec.luau` against the fake DataStore.
- Anything user-facing: the docs page that covers it, and a line in `CHANGELOG.md` under Unreleased.

A feature that touches storage should be tested on both the memory backend and the DataStore backend.

## Style

- `--!strict` in every file under `src/`.
- Errors go through `error("rSQL: ...", 0)` or `Errors.raise`, start with `rSQL:` and say what to do when there's something to do.
- Comments explain why, not what. Keep them short.
- No new runtime dependencies (see `docs/adr/0004-no-dependencies.md`).

## Benchmarks and figures

If a change affects performance, run `lune run bench/run` and include the before and after numbers in the pull request. `lune run scripts/figures` rebuilds the HTML for the README charts; `swift tools/render-figures.swift` turns them into PNGs on macOS.

## Releases

Bump `src/Version.luau` and `wally.toml`, move the Unreleased notes in `CHANGELOG.md` under the new version, and push a `vX.Y.Z` tag. The release workflow builds the model file, attaches it to a GitHub release and publishes to Wally.
