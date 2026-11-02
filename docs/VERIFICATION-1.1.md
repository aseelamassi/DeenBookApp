# Verification — Flutter 1.1 / API ledger v2 — 2026-10-23

Toolchain: Flutter 3.47.7 stable, Dart 3.13.5, .NET SDK 10.0.401, EF Core 10.0.12, Linux host.

## Completed checks

- Flutter automated suite: **50 tests passed**. Includes the original 37 authentication/storage/UI/PDF tests, five ledger arithmetic tests, seven new UI workflow tests, and a long invoice PDF test.
- `flutter analyze --no-pub`: no issues. Analysis repeated after the final PDF and filter-label adjustments.
- Updated API automated suite: **51 tests passed**, covering tenant isolation, subscription restrictions, refresh-token rotation/replay, unique phone login, pending transfers, invoice snapshots and legacy request compatibility. Build completed without warnings or errors.
- API integration tests confirm that pending transfers do not change balances or receipts, another shop cannot confirm them, suspended shops are blocked, and concurrent confirmation plus an original request retry affects the balance exactly once.
- Invoice tests verify discount arithmetic, customer credit, product edits not changing previous invoice prices, secondary contacts, filtered pagination counts and category retrieval.
- Old saved requests keep their original idempotency behavior after the API upgrade. Changed requests with the same operation ID receive a conflict.
- Flutter tests verify quantity parsing/rounding, explicit choice to retain cash change, secondary contact and signed opening credit, one request for discount plus paid amount, pending-transfer payload, optional receipt sharing, legacy API field gating and blocking a modern saved draft on an old API.
- Layout tests at 320, 390 and 768 logical pixels. Login, empty/populated home and supplier screenshots are generated from test fixtures and visually inspected. Cards use Material surfaces so checkbox/list-tile interaction remains visible.
- Arabic PDF generation uses bundled Cairo fonts. A 100-item invoice with a long description was rendered and inspected across multiple pages. Column widths are constrained to keep repeated headers legible. The native print dialog was not exercised.
- EF migration `20261023205608_AddModernLedger` generated for SQL Server. `migrations has-pending-model-changes` reports none. An idempotent SQL upgrade from `AddPhoneLoginAndRefreshTokens` was generated and inspected; new invoice snapshots default to `[]` for previous entries.
- **Web release compilation succeeded**, including the Wasm compatibility dry run. A separate Wasm runtime build was not tested. The compilation parameter `https://api.example.test` is a placeholder, not a deployed API.

## Integration limits

The Flutter network tests use an injected Dio adapter; API integration tests run the actual ASP.NET Core application against isolated SQLite databases. Neither connects to the user's deployed service or production database. The SQL Server upgrade script has not been executed against a live SQL Server. Migration history must be reconciled with the user's current branch, particularly if its original migrations were deleted or recreated.

No Android APK/AAB or iOS IPA was built or installed. Release signing, real-device Keychain/Keystore persistence, microphone permission and recognition, physical printing, WhatsApp/share-sheet behavior, and live connectivity remain device checks.

The application contains no login bypass or sample customer/ledger records; fixtures are in `test/` only. Public self-signup, worker memberships/permissions, online subscription checkout and self-service password recovery remain unimplemented server features. Existing UI directs account/subscription requests to administration and labels workers as unavailable. Subscription activation is controlled by the API.
