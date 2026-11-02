# Verification — Flutter 1.1.1 — 2026-10-28

Toolchain: Flutter 3.47.7 stable and Dart 3.13.5, Linux.

## Startup helper follow-up — 2026-10-28

The follow-up adds only `Start-DeenBook.ps1` and documentation. Flutter/Dart source, dependencies, platform files, existing tests, and embedded backend remain byte-for-byte unchanged from the previously verified 1.1.1 archive. The Flutter checks below are the earlier results, not a new Flutter run during this follow-up.

- PowerShell 7.6.9 on Linux parsed and executed the helper successfully. **54 automated assertions passed** in an isolated harness using a fake native Flutter executable and a mocked HTTP boundary. The checks cover base URL normalization and rejection, international support numbers, the unauthenticated route, check-only mode, stopping before Flutter on HTTP errors, exact Flutter arguments, working directory restoration, missing tools/project files, and failing dependency/run commands.
- A separate real `-CheckOnly` invocation reached the HTTPS plans URL and returned HTTP 503 from this environment. The helper reported the hosting error and exited with code 1, without starting Flutter. Read-only HTTP access to `/api/subscription` returned 401. HTTPS remains an external configuration/access issue to resolve; these observations do not establish its hosting-side cause.
- The helper does not follow redirects, disable certificate validation, send credentials, read response bodies, submit subscription requests, or change the database/hosting configuration. HTTP 401 is documented only as an unauthenticated reachability result.
- The script uses Windows PowerShell 5.1-compatible syntax and UTF-8 BOM for Arabic. Windows PowerShell 5.1 and a Windows Flutter installation were not available for execution here. Native Windows invocation and a real device remain to be checked on the user's computer.
- No production support number was supplied; the helper validates an optional number but does not invent or store one in source. No new migration or application binary was produced.

## Completed checks

- Full Flutter suite: **66 passed, 0 failed** (50 existing tests plus 16 connection/subscription regressions).
- `flutter analyze --no-pub`: **no issues found**.
- Web release compilation succeeded using `API_BASE_URL=https://api-deenbook.runasp.net`; the Wasm compatibility dry run also succeeded. A separate Wasm runtime build was not exercised.
- Real Dio request composition with injected adapters confirms that host URLs ending with `/`, `/api`, `/api/` or `/api.` reach exactly one `/api/auth/login` prefix. Hosted subdirectories remain intact.
- Release configuration continues to require HTTPS. Certificate verification is not bypassed, and HTTP is not silently upgraded. Requests do not automatically follow redirects.
- Tests distinguish connection, timeout, TLS, redirect, missing-route and server errors. Server 5xx details are not exposed. HTML or malformed login responses do not create a session.
- Missing administration contact does not claim a sent request or write to the clipboard automatically. Explicit copying retains the complete request and reports that it was not sent.
- A successful WhatsApp launcher result means only that a draft link opened. Tests verify the destination and request text and require user-facing instructions to send in WhatsApp. Launcher failure offers the number and explicit copying.
- Subscription text uses the selected 60 ILS / one-month or 150 ILS / three-month plan. Support numbers accept international + or 00 notation; invalid/unconfigured numbers remain unavailable.
- The new fallback dialog was rendered and visually inspected at 320 logical pixels. Existing login, home, supplier and ledger layout/golden tests also passed.

## Live observations and limits

Unauthenticated GET checks on 2026-10-27 and repeated on 2026-10-28 received HTTP 401 from the deployed `/api/subscription` route over HTTP. HTTPS attempts from the verification environment failed with a 503 upstream connection error. This does not establish the hosting-side cause. HTTPS activation/certificate configuration must be checked on the hosting account. No deployment settings were changed.

No credentials were sent to the deployed API, no shop records or payments were created, and no live authenticated login or subscription renewal was tested. Connection regression tests use injected HTTP adapters. No WhatsApp messages were sent.

No Android APK/AAB or iOS IPA was built or installed. Real-device secure storage, browser CORS, native external-app launching, and live HTTPS login still need environment checks. `SUPPORT_PHONE` must be supplied with the actual administration number; no number was invented or embedded.

The current request flow is manual contact with administration. This update does not implement public registration, an API inbox for subscription requests, employee memberships, online payment collection or automatic subscription activation.

The embedded backend was synchronized byte-for-byte with the standalone Backend archive from 2026-10-25. It was not changed or retested as part of this Flutter fix; its own verification report documents the earlier 58 backend tests. This Flutter update requires no new migration. Previous Flutter 1.1 verification remains in `VERIFICATION-1.1.md`.
