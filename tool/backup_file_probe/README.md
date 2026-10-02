# Step 14-C2 Android file probe

This is a verification tool, not the production Export/Import feature. It does not
parse Backup v1, access real application data, or invoke restore. The production
`lib/main.dart` is unchanged. Native channel registration is limited to debuggable
Android applications; the Dart entrypoint refuses non-debug execution.

## Run

From the repository root:

```powershell
flutter run --debug --target lib/platform_probe/main_backup_file_probe.dart
```

The fixed payload is UTF-8 (including the final newline):

```text
Keep My Car Step 14-C2 probe
日本語
1234567890
```

Suggested filename: `KeepMyCar_Backup_Probe.kmcbackup`. The probe uses
`application/octet-stream` because the fixed payload is not a JSON backup and
the custom filename should be preserved. Production Backup v1 MIME selection
is a separate decision. Import uses `*/*` and `CATEGORY_OPENABLE`, single-file
selection only. No metadata query, persistent URI grant, storage permission,
folder access, or new package is used.

## Safety contract

- Save opens the output stream with explicit truncation mode `"wt"`, intending
  to remove old trailing bytes when overwriting an existing file. If the provider
  rejects this mode, the exception becomes an error, never success.
  The app guarantees the request, not provider compliance: a provider that accepts
  `"wt"` but fails to truncate is outside this verified contract.
- Native save success means open, write, explicit flush, and close all completed
  without an exception. Null streams are errors. This does not guarantee remote
  provider synchronization or removal of partial files on failure.
- Native read success means EOF and close both completed. Partial bytes are never
  returned as success after an error. The actual accumulated read limit is
  `PROBE_MAX_READ_BYTES` (temporarily 5 MiB); exactly 5 MiB is allowed.
- Only `RESULT_CANCELED` means cancelled. `RESULT_OK` without URI is missingUri.
  Unexpected results, conflicting/multiple ClipData, and non-content URIs fail.
- The OS picker has no timer. The I/O deadline is `PROBE_IO_TIMEOUT_MS` (60 s),
  starting after valid URI selection and including open and close. Timer delivery
  and final completion also use monotonic elapsed time. A suspended process cannot
  promise delivery at precisely 60 seconds; delayed completion cannot become success.
- Timeout completes the channel request once as error/timeout but leaves the
  native gate busy until the actual worker exits. Blocking I/O is not forcibly
  interrupted. Subsequent requests return busy. Cleanup during I/O retains this
  process-wide gate across Activity recreation until actual worker completion.
- Normal backgrounding does not terminate selection or I/O. Cleanup abandons the
  operation, attempts interrupted while the old messenger exists, clears its
  reply callback and Activity reference, and unregisters the handler. No state is
  restored into the new Activity. Process death cannot deliver a result to a dead
  Dart isolate. A surviving engine receives an interrupted reply when transport
  is still available; delivery through an already dead messenger is not guaranteed.
- Request codes are not recycled within a process. A saved watermark prevents
  reuse when restoring Activity state after process death. Exhaustion fails closed
  rather than reusing a code. No third-party plugin is currently using this range;
  future native integrations must review its reservation (0x6000..0x7fff).
- MainActivity stays a FlutterActivity. Its existing onActivityResult path calls
  super before forwarding to this probe. configureFlutterEngine and cleanup call
  super so normal Flutter plugin registration/forwarding are retained.
- Dart returns typed success/cancelled/error results with fixed error codes.
  Exception text and stack traces are not returned. The probe widget checks mounted
  after awaiting a result. Backup validation and restore remain separate.

## Automated checks without new dependencies

```powershell
dart format lib test
flutter analyze
flutter test
& .\tool\backup_file_probe\run_checks.ps1
flutter build apk --debug --target lib/platform_probe/main_backup_file_probe.dart
git diff --check
```

The JVM checks compile the same `BackupFileOperation.kt` that Android uses. They
use plain Kotlin `check`, the existing Kotlin compiler/stdlib jars in the local
Gradle cache, and the existing Android Studio JBR. There is no JUnit dependency or
Gradle configuration change. The script fails if the existing jars are absent;
it never downloads dependencies. Java/cache locations can be supplied as parameters.

Covered: save/read bytes, empty input, null streams, URI null, Cancel/unexpected
result, multiple selection, partial read failure, write/flush/read/close failures,
combined failures, SecurityException, FileNotFoundException, IOException,
IllegalArgumentException, RuntimeException, 5 MiB boundaries, 60-second boundaries,
timeout/cleanup/late-success competition, double result, busy, old-owner cleanup,
Activity request watermark, and detached messenger failure. Time is supplied to
the state object; checks do not wait 60 seconds. Android Intent launch, actual
Handler delivery and embedding lifecycle wiring require device/review verification.

The checks also model a provider with larger existing contents: `"wt"` followed
by shorter bytes leaves exactly the new bytes. A `"w"` negative control retains
the old tail, and rejection of `"wt"` returns error without fallback. These are
fake-provider contract checks, not actual DocumentsProvider verification.
The script separately guards the Android save wiring to require the explicit
`resolver.openOutputStream(uri, "wt")` call passed to `BackupStreamIo.save` and
reject alternate output opens. Mode-less / `"w"` regressions fail this inspection;
source refactoring requires review and an update to the guard.

## Pixel 6a results

User-reported verification using the probe APK:

| Item | Result |
|---|---|
| 1. Save | PASS |
| 2. Save Cancel | PASS |
| 3. Read | PASS |
| 4. Read Cancel | PASS |
| 5. Saved/read bytes exactly equal | PASS |
| 6. Overwrite a larger existing file with the same name | 未実施 (not performed) |

For item 6, the Android save provider did not offer overwrite confirmation or
return the existing file URI; it created a separate file with `(1)` in its name.
This is not an app failure and is not counted as an overwrite test. There was no
observed failed overwrite or retained old tail. The `"wt"` contract is reinforced
by the automated checks/source inspection above and code review; actual overwrite
behavior of this provider remains untested.

## Pixel 6a checklist

1. Save fixed bytes into a chosen local folder. Confirm the requested .kmcbackup
   name, success, and the actual file's contents.
2. Start save again and press Android Back. Confirm cancelled, never success/error.
3. Read the saved file. Confirm success and `固定bytes一致：true`.
4. Start read again and press Android Back. Confirm cancelled.
5. Confirm the read bytes exactly match the fixed payload above (including the final newline).
6. Overwrite a disposable test file larger than the fixed payload. Confirm the
   resulting size and contents exactly match the new bytes, with no old tail.
   Verify that the provider actually overwrote the existing file: CREATE_DOCUMENT
   may instead create a new file with a suffixed name. That is not an overwrite test.

Do not clear application data or uninstall to switch entrypoints. To return to
the production app, build/run `lib/main.dart` with the same application ID.

## Reference APIs

- [Android Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files)
- [ContentResolver](https://developer.android.com/reference/android/content/ContentResolver)
- [FlutterActivity](https://api.flutter.dev/javadoc/io/flutter/embedding/android/FlutterActivity.html)
- [Kotlin use](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.io/use.html)
