# 0002: Replace the 1.x parser with a recursive-descent parser

Accepted, 2.0.0.

## Context

1.x parsed SQL with string patterns plus a small YACC-style grammar added in 1.2. It handled the quick-start queries, but:

- `OR` was read as `AND`, and parentheses weren't supported
- `LIKE` was turned into a Lua pattern, so it matched anywhere in the value and broke on characters like `-` or `.`
- no `JOIN`, `GROUP BY`, `ORDER BY`, `LIMIT`, math or functions
- errors said a step failed but not where in the query

## Decision

A hand-written lexer and recursive-descent parser:

- the lexer tracks the offset of every token, handles both quote styles with doubled-quote escapes, backtick identifiers, comments, numbers with exponents and `?` / `:name` parameters
- the parser has one function per statement and one per precedence level for expressions, and produces a typed syntax tree (`SQL/Ast.luau`)
- every node keeps its offset, so errors can show a line, a column and a caret
- unknown words get a "did you mean" from an edit-distance search over the keywords, tables or columns that would fit

## Options I looked at

- **A parser generator.** Nothing that targets Luau is maintained, and generated tables are hard to give good error messages from.
- **Extending the 1.x parser.** Each feature added more special cases; precedence and positions would have meant rewriting it anyway.

## Consequences

- About 660 lines for the parser and 200 for the lexer, all covered by `tests/unit/Sql.spec.luau`.
- Parsing is fast enough not to matter (about 38,000 statements a second under Lune), and the statement cache means each distinct query is parsed once.
- The grammar is a subset of SQL, and the docs list exactly what's in it.
