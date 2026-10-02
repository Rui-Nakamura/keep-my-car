# Production backup file I/O checks

`BackupTransfer` connects the current `PersistentPlanState.snapshot` to the
existing `BackupV1Codec` and `BackupFileGateway`. `readCandidate()` performs full
validation without saving; presentation can confirm replacement before calling
`restore(candidate)`, which uses `PersistentPlanState.restoreFromBackup` / Safe Save.
The final UI is Step 14-D. The fixed-byte C2 Dart entrypoint has been removed.

Android registers `keep_my_car/backup_file` in debug and release. Its only methods
are save/read. Save requests `openOutputStream(uri, "wt")` without fallback and
requires write, flush and close. Read requires EOF and close, permits exactly
5 MiB and rejects any additional byte. No metadata query or storage permissions
are used. The picker has no timeout; URI-selected I/O has a 60-second monotonic
deadline. Timeout/cleanup reject late success, and the process gate stays busy
until the worker exits. Existing request watermark and lifecycle protection remain.
Provider compliance with truncation and remote synchronization are not guaranteed.

Export uses `application/octet-stream` to preserve the custom `.kmcbackup` name;
Import selects a single openable `*/*` file and validates its contents.

Run from the repository root:

```powershell
flutter analyze
flutter test
& .\tool\backup_file\run_checks.ps1
flutter build apk --release
git diff --check
```

The existing cached Kotlin compiler and Android Studio JBR compile the same
`BackupFileOperation.kt` used in Android. No test dependency is added/downloaded.
The script checks the explicit wt call with no alternate output open. JVM checks
cover stream ordering/failures, real read size boundaries, cancel, timeout, late
success, cleanup, busy gating and request watermark. Device verification is still
needed for actual provider, picker and Flutter embedding lifecycle behavior.

C2 device results are historical: Pixel 6a save, save cancel, read, read cancel,
and exact bytes passed. Actual overwrite was not performed because the provider
created a suffixed new file. These results do not establish C3 device acceptance.
The original C2 tool and full record remain in checkpoint `21cfedd` Git history.
