# Protocol fixtures

One JSON file per WebSocket message. Both test suites read this folder:

- Swift: `Tests/ShortcutPhoneCoreTests/ProtocolContractTests.swift`
- TS: `web/tests/protocol-contract.test.ts`

`valid/client-*` and `valid/server-*` must decode (and Swift must re-encode them to the same
JSON). `invalid/*` must be rejected. The web suite parses only `server-*` messages; it
checks its `client-*` builders against the valid client fixtures. Update these first when the protocol changes.
