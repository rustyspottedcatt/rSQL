## What this changes

## Checklist
- [ ] `lune run tests/run` passes
- [ ] `stylua --check src tests scripts bench examples` and `selene src tests` are clean
- [ ] `luau-lsp analyze --platform=standard --definitions=types/globals.d.luau --ignore="src/**/*.server.luau" src` reports no errors
- [ ] `lune run scripts/emulate-studio` passes
- [ ] New SQL syntax has parser tests, and new behavior is tested on both the memory and DataStore backends
- [ ] CHANGELOG.md is updated if users will notice the change
