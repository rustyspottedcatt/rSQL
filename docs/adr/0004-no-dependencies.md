# 0004: No runtime dependencies

Accepted, 2.0.0.

## Context

1.x shipped a full copy of evaera/promise 4.0 inside its `Packages` folder, test files and tooling configs included. Games that already used another Promise version ended up with two copies, and the library was large for the handful of methods 1.x scripts call.

## Decision

rSQL ships no runtime dependencies. `db:exec` is synchronous (it yields while DataStore calls run, like any DataStore code). For 1.x compatibility there's a small promise in `src/Promise.luau` with the parts 1.x scripts call: `new`, `resolve`, `reject`, `andThen`, `catch`, `finally`, `await`, `expect`, `getStatus`.

## Options I looked at

- **Keep evaera/promise as a Wally dependency.** Full-featured, but people who install the model file would still need it, and the new API doesn't use promises at all.
- **Return promises from the new API too.** Adds a layer to every call for no benefit in Roblox, where yielding functions are the normal style.

## Consequences

- One ModuleScript to install.
- The bundled promise is not a full Promise/A+ implementation: no cancellation, no `Promise.all`. Code that needs those can wrap `db:exec` in its own promise library.
