DeenBook - Offline reliability / 7-day grace patch
BASELINE: original Nov 27 app/backend + previously delivered Worker Delete Fix applied.

SCOPE: 168-hour maximum from the last successful authenticated subscription request; warnings at elapsed days 5 and 6 and lock/warning at day 7; no new local writes after expiry; cached subscription reads cannot extend the period. Existing local financial records and pending worker deletion requests are retained. On successful live verification, grace resets even if individual operations remain rejected; sync errors remain visible. Offline access also remains limited by subscription expiry. Clock rollback detection is best effort: no offline client can guarantee protection against a compromised device or clock.

- Core Flutter archive: account-bound new financial outbox and drafts, quarantine old unidentified outbox entries (retained in original storage; never assign to another account), foreground warning/lock and automatic retry while app runs, sequential catalog pagination, no new dependencies. Old unassigned drafts are retained under their old key and not auto-loaded. Existing worker-deletion fix is a prerequisite.
- Native notifications archive: optional separate proposed Android manifest/permission/receiver changes and iOS bridge; review and approve before applying. Android 13+ asks notification permission. Android inexact alarms may be delayed by power-saving or force-stop; reboot receiver reschedules when possible. iOS permissions and OS behavior apply. Notifications require one successful online verification after installing (or restoring a valid cached session); foreground warning works without native patch.
- Backend patch: actor-aware operation replay, including soft-voided IDs, and server verification timestamp in response. No migration or configuration changes in this patch. Previous worker-delete migration remains prerequisite.

NOT COMPLETE: SQLite migration, offline create/update/delete for customer/supplier/product, worker enrollment/rename, credit-limit and settings mutations, void/confirm and local reports/exports remain to implement with server-safe idempotent queue, dependencies and projections. Do not represent this as full offline-first coverage. JSON secure-storage remains and large datasets may be slow. No changes to SDK constraints, Gradle, iOS deployment target, package versions, API URL, signing or database configuration.

INSTALL: backup app/server data. Replace files using their relative paths in the existing projects. Do not clear app storage or uninstall. Apply backend archive first; then core Flutter. If approved, apply native notifications archive as well.

TEST (SDK not available in preparation environment; not built or run):
  dotnet test tests/DeenBook.Tests/DeenBook.Tests.csproj --filter FullyQualifiedName~OfflineActorTests
  flutter analyze
  flutter test test/offline_grace_test.dart test/offline_test.dart test/offline_integration_test.dart test/worker_delete_sync_test.dart
  flutter build apk --release --split-per-abi
  Validate merged manifest minSdk, armv7 and arm64 APKs on real supported low-RAM Android 7/8 devices (Android 6 only if dependency/Flutter minSdk allows), iOS 15+ and notification permission denied/allowed, reboot/Doze, expired and revoked accounts, switching account with pending items, >100 customers, weak network, and server restart. Test day thresholds by setting a test identity verifiedAt to 5, 6, 7 elapsed days, not by changing production device time.
