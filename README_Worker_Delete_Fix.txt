DeenBook — worker deletion fix (Flutter)

Copy lib/ and test/ files into the matching locations in your existing Flutter project. No configuration or dependencies were changed. Deploy the updated backend and its data migration first.

After the upgrade, sign in online as the owner and load the workers screen at least once to establish verified owner identity and the offline worker snapshot. When offline, deletion is saved securely in an owner/shop-scoped queue and the worker is hidden locally. The pending request remains visible in the worker screen and Sync Center, including after restart. It is replayed against the original worker ID automatically through the existing periodic synchronization, or manually. Rejected requests remain pending with the error; no false success is shown. A new worker still requires online access and successful deletion synchronization. Pending administrative requests do not enter financial report counts.

An offline worker cannot be remotely signed out before their device contacts the server. The owner's deletion is not effective server-side until synchronization succeeds. Existing financial outbox attribution/recovery for transactions created on a deleted worker's device is unchanged; those are a separate data-reconciliation issue.

Run: flutter analyze
Run: flutter test test/worker_delete_sync_test.dart
The Flutter/Dart SDK is not available here; these tests and app build have NOT been executed.
